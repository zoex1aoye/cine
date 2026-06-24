import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

class CineVideoControls extends StatefulWidget {
  final VideoState state;
  final String? title;
  final VoidCallback? onBack;
  final String? previewUrl;

  const CineVideoControls(
    this.state, {
    super.key,
    this.title,
    this.onBack,
    this.previewUrl,
  });

  @override
  State<CineVideoControls> createState() => _CineVideoControlsState();
}

class _CineVideoControlsState extends State<CineVideoControls> {
  bool _showControls = false;
  Timer? _hideTimer;
  Timer? _indicatorTimer;

  // Dual Player Preview State
  Player? _previewPlayer;
  VideoController? _previewController;
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _isPreviewReady = false;
  bool _isConfirmingSeek = false;
  bool _wasPlayingBeforeDrag = false;
  Timer? _previewDisposeTimer;
  Timer? _seekDebounceTimer;
  Timer? _smartWarmUpTimer;
  bool _warmUpInProgress = false;
  // 预览上次 seek 的目标位置（毫秒）。-1 表示尚未定位。
  // 用于"少 seek 多播放"策略：仅当手指移动超过阈值才重新定位。
  double _previewSeekTarget = -1;

  // 进度条拖动死区（迟滞）半径，单位：物理像素。
  // 触摸屏上手指压住进度条时电容噪声会 ±数像素抖动；半径必须大于抖动幅度，
  // 才能吸收"微小前进后退"，避免被误判为拖动。同时也充当起步 slop：
  // 从按下点起，手指要真正推过该距离才开始更新 _dragValue / 预览。
  static const double _kSliderDeadbandPx = 10.0;
  // 极短视频下 msPerPixel 很小，给死区一个时间下限，防止过敏。
  static const double _kSliderDeadbandFloorMs = 1200.0;

  // Gestures
  double _brightness = 0.5; // App-level brightness
  double _volume = 100.0;
  
  // Indicator State
  String _indicatorText = '';
  IconData? _indicatorIcon;
  bool _showIndicator = false;

  Player get player => widget.state.widget.controller.player;

  /// 预览源是否为备用线路（与主路 URL 不同才值得后台预热，避免双倍拉同一 CDN）
  bool get _previewIsBackupLine {
    final previewUrl = widget.previewUrl;
    if (previewUrl == null || previewUrl.isEmpty) return false;
    final medias = player.state.playlist.medias;
    final idx = player.state.playlist.index;
    if (medias.isEmpty || idx < 0 || idx >= medias.length) return true;
    return previewUrl != medias[idx].uri;
  }

  bool get _canScheduleWarmUp =>
      _previewIsBackupLine &&
      !_isBuffering &&
      !_isDragging &&
      !_isConfirmingSeek &&
      _previewPlayer == null &&
      !_warmUpInProgress;

  late StreamSubscription _playingSub;
  late StreamSubscription _positionSub;
  late StreamSubscription _durationSub;
  late StreamSubscription _volumeSub;
  late StreamSubscription _bufferingSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isBuffering = false;

  // 弱网提示：记录缓冲开始时间，持续超过 5s 显示提示
  DateTime? _bufferingStartTime;
  Timer? _bufferingUiTimer;
  bool _showWeakNetHint = false;

  @override
  void initState() {
    super.initState();
    _volume = player.state.volume;
    _playing = player.state.playing;
    _position = player.state.position;
    _duration = player.state.duration;

    ScreenBrightness().current.then((value) {
      if (mounted) setState(() => _brightness = value);
    });

    _playingSub = player.stream.playing.listen((event) {
      if (mounted) {
        setState(() => _playing = event);
        if (event && !_isBuffering) {
          _scheduleSmartWarmUp(const Duration(seconds: 10));
        }
      }
    });
    _positionSub = player.stream.position.listen((event) {
      // 只在控件显示时才触发重绘，隐藏时仅更新内存值，降低移动端 CPU 占用
      if (mounted && !_isDragging) {
        _position = event;
        if (_showControls) setState(() {});
      }
    });
    _durationSub = player.stream.duration.listen((event) {
      if (mounted) setState(() => _duration = event);
    });
    _volumeSub = player.stream.volume.listen((event) {
      if (mounted) setState(() => _volume = event);
    });
    _bufferingSub = player.stream.buffering.listen((event) {
      if (!mounted) return;
      setState(() => _isBuffering = event);
      // 主播放器缓冲时暂停预览下载，把带宽/解码资源让给主路
      if (event) {
        _previewPlayer?.pause();
        _cancelSmartWarmUp();
        _bufferingStartTime ??= DateTime.now();
        // 5s 后显示弱网提示
        _bufferingUiTimer ??= Timer(const Duration(seconds: 5), () {
          if (mounted && _isBuffering) {
            setState(() => _showWeakNetHint = true);
          }
        });
      } else {
        _bufferingStartTime = null;
        _bufferingUiTimer?.cancel();
        _bufferingUiTimer = null;
        if (_showWeakNetHint) setState(() => _showWeakNetHint = false);
        if (_playing && _canScheduleWarmUp) {
          _scheduleSmartWarmUp(const Duration(seconds: 5));
        }
      }
    });

    // 播放稳定后尝试智能预热；全屏/控件展开时缩短等待（用户更可能拖动）
    if (_playing && !_isBuffering) {
      _scheduleSmartWarmUp(const Duration(seconds: 10));
    }
  }

  @override
  void didUpdateWidget(CineVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Preview URL changed (speed test found faster backup, or episode switched).
    // Reload the warmed-up preview player with the new source.
    if (widget.previewUrl != oldWidget.previewUrl &&
        widget.previewUrl != null &&
        widget.previewUrl!.isNotEmpty &&
        _previewPlayer != null) {
      // 不重置 _isPreviewReady：保留上一帧画面，避免切源时预览窗黑屏闪烁。
      // 新源解码出首帧后 Video 会自动刷新；拖动中则立即对齐到手指位置。
      _previewSeekTarget = -1;
      _previewPlayer!.open(Media(widget.previewUrl!), play: false);
      if (_isDragging && _isPreviewReady) {
        _seekPreview(_dragValue);
      }
    }
  }

  @override
  void dispose() {
    _cancelSmartWarmUp();
    _previewDisposeTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _previewPlayer?.dispose();
    ScreenBrightness().resetScreenBrightness();
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _bufferingUiTimer?.cancel();
    _playingSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _volumeSub.cancel();
    _bufferingSub.cancel();
    super.dispose();
  }

  void _toggleControls() {
    if (_isConfirmingSeek) {
      _cancelSeek();
      return;
    }
    final willShow = !_showControls;
    setState(() {
      _showControls = willShow;
    });
    if (willShow) {
      _startHideTimer();
      if (widget.state.isFullscreen()) {
        _scheduleSmartWarmUp(const Duration(milliseconds: 500));
      }
    } else {
      _hideTimer?.cancel();
    }
  }

  void _scheduleSmartWarmUp(Duration delay) {
    if (!_canScheduleWarmUp) return;
    _smartWarmUpTimer?.cancel();
    _smartWarmUpTimer = Timer(delay, () {
      if (mounted && _canScheduleWarmUp) {
        _warmUpPreviewPlayer();
      }
    });
  }

  void _cancelSmartWarmUp() {
    _smartWarmUpTimer?.cancel();
    _smartWarmUpTimer = null;
  }

  /// 主路播放稳定且未缓冲时，后台预热预览播放器并定位到当前进度。
  /// 仅在备用线路可用时启用，避免与主路抢同一 CDN 连接。
  void _warmUpPreviewPlayer() {
    if (!_canScheduleWarmUp) return;
    _cancelSmartWarmUp();
    _createPreviewPlayer(initialSeekMs: _position.inMilliseconds.toDouble());
  }

  void _enterFullscreenWithWarmUp() {
    widget.state.enterFullscreen();
    _scheduleSmartWarmUp(const Duration(milliseconds: 800));
  }

  void _exitFullscreen() {
    widget.state.exitFullscreen();
    _cancelSmartWarmUp();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showActionIndicator(IconData icon, String text) {
    setState(() {
      _indicatorIcon = icon;
      _indicatorText = text;
      _showIndicator = true;
    });
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showIndicator = false);
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (!widget.state.isFullscreen()) return; // Disable in portrait mode
    
    _startHideTimer();
    final dy = details.delta.dy;
    if (details.globalPosition.dx < screenWidth / 2) {
      // Left side: Real Screen Brightness
      setState(() {
        _brightness -= dy * 0.005;
        _brightness = _brightness.clamp(0.0, 1.0);
      });
      ScreenBrightness().setScreenBrightness(_brightness);
      final brightnessPercent = (_brightness * 100).round();
      _showActionIndicator(Icons.brightness_medium, '$brightnessPercent%');
    } else {
      // Right side: Volume
      setState(() {
        _volume -= dy * 0.5; // Up decreases dy, so we subtract
        _volume = _volume.clamp(0.0, 100.0);
      });
      player.setVolume(_volume);
      _showActionIndicator(
        _volume == 0 ? Icons.volume_off : Icons.volume_up, 
        '${_volume.round()}%'
      );
    }
  }

  /// Internal: create preview player, configure mpv, and open media.
  void _createPreviewPlayer({double? initialSeekMs}) {
    _warmUpInProgress = true;
    _previewPlayer = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error));
    _previewPlayer!.setVolume(0.0);
    // Linux: 禁用硬解纹理共享，与主播放器保持一致，规避 VAAPI-OpenGL EGL 互操作崩溃
    _previewController = VideoController(_previewPlayer!, configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: !Platform.isLinux,
    ));

    if (_previewPlayer!.platform is NativePlayer) {
      final native = _previewPlayer!.platform as NativePlayer;
      native.setProperty('hr-seek', 'no');
      native.setProperty('vd-lavc-skiploopfilter', 'all');
      native.setProperty('vd-lavc-fast', 'yes');
      // Linux: vaapi-copy（不依赖 OpenGL 互操作，与像素拷贝渲染路径兼容）
      // 其他平台: auto（让 MPV 自动选择最优硬解，与主播放器对齐）
      native.setProperty('hwdec', Platform.isLinux ? 'vaapi-copy' : 'auto');
      // 同样设置 hwdec-codecs，确保 VP9/AV1 预览也走硬解
      native.setProperty('hwdec-codecs', 'h264,hevc,vp8,vp9,av1,mpeg4,mpeg2video,vc1,wmv3');
      native.setProperty('force-seekable', 'yes');
      native.setProperty('vd-lavc-threads', '0');
      native.setProperty('vd-lavc-dr', 'yes');

      // 预览窗口仅 160×90，缓冲尽量小，避免拖动时与主播放器抢带宽
      final isMobile = Platform.isAndroid || Platform.isIOS;
      final previewBuf = isMobile ? '4194304' : '8388608'; // 4 MB / 8 MB
      final previewReadahead = isMobile ? '3' : '5';
      native.setProperty('cache', 'yes');
      native.setProperty('cache-secs', previewReadahead);
      native.setProperty('demuxer-readahead-secs', previewReadahead);
      native.setProperty('demuxer-max-bytes', previewBuf);
      native.setProperty('cache-pause-initial', 'no');
      native.setProperty('cache-pause-wait', '1');
      // 预览只需快速出帧：缩小探测窗口 + 低分辨率解码（160×90 窗口足够）
      native.setProperty('demuxer-lavf-probesize', '1048576');  // 1 MB
      native.setProperty('demuxer-lavf-analyzeduration', '1');
      native.setProperty('vf', 'scale=160:-2');
      // 预览播放器同样启用 HLS 并行分片 + 较大读缓冲，保证拖动时帧响应速度
      native.setProperty('demuxer-lavf-o', 'http_multiple=1');
      native.setProperty('demuxer-lavf-o', 'icy=0');
      native.setProperty('stream-buffer-size', isMobile ? '262144' : '524288');
      native.setProperty('demuxer-thread', 'yes');

      // 预览强制走最低码率变体：分片体积小，下载/解码都快，
      // 小窗 160×90 画质再低也无所谓（仅预览，非主播放器）。
      // 单码率源时 min == max，无副作用。
      native.setProperty('hls-bitrate', 'min');

      // 可定位缓存：已下载的分片留在内存，来回拖动 / 播过的段落几乎瞬时命中，
      // 减少"少 seek 多播放"策略下的重复下载。
      native.setProperty('demuxer-seekable-cache', 'yes');
    }

    // Open the backup source (or fall back to main player's current media)
    final mediaList = player.state.playlist.medias;
    final idx = player.state.playlist.index;
    if (widget.previewUrl != null && widget.previewUrl!.isNotEmpty) {
      _previewPlayer!.open(Media(widget.previewUrl!), play: false);
    } else if (mediaList.isNotEmpty && idx >= 0 && idx < mediaList.length) {
      _previewPlayer!.open(mediaList[idx], play: false);
    }

    // Mark ready when first video frame is decoded.
    _previewPlayer!.stream.width.listen((w) {
      if (mounted && !_isPreviewReady && w != null) {
        setState(() => _isPreviewReady = true);
        _onPreviewReady(initialSeekMs);
      }
    });

    // Safety net: re-seek when duration is confirmed (media fully demuxed)
    late final StreamSubscription<Duration> durSub;
    durSub = _previewPlayer!.stream.duration.listen((dur) {
      if (dur > Duration.zero && mounted && _isPreviewReady) {
        durSub.cancel();
        _onPreviewReady(initialSeekMs);
      }
    });
  }

  /// 预览首帧就绪：拖动中立即跟手；闲置预热则定位到当前进度并暂停。
  void _onPreviewReady(double? initialSeekMs) {
    _warmUpInProgress = false;
    if (_isDragging || _isConfirmingSeek) {
      _alignPreviewToDrag();
      return;
    }
    final targetMs = initialSeekMs ?? _position.inMilliseconds.toDouble();
    _previewSeekTarget = targetMs;
    _previewPlayer?.seek(Duration(milliseconds: targetMs.toInt()));
    _previewPlayer?.pause();
    _schedulePreviewDispose();
  }

  /// 预览解码就绪 / 切源后，把预览对齐到当前拖动目标：
  /// 拖动中 → seek + 向前播放（理解 A）；确认中 → 仅 seek 定格目标帧；预热闲置 → 不动。
  void _alignPreviewToDrag() {
    if (_isDragging) {
      _seekPreview(_dragValue);
    } else if (_isConfirmingSeek) {
      _previewSeekTarget = _dragValue;
      _previewPlayer?.seek(Duration(milliseconds: _dragValue.toInt()));
    }
  }

  /// 定位预览到指定位置并向前连续播放（理解 A：可播放预览）。
  /// 依赖 hr-seek=no：seek 会落到目标前最近的关键帧（略微靠前），
  /// 首帧立刻可出，随后向前播放"追上"手指位置，观感更丝滑。
  void _seekPreview(double ms) {
    _previewSeekTarget = ms;
    _previewPlayer?.seek(Duration(milliseconds: ms.toInt()));
    _previewPlayer?.play();
  }

  /// Ensure preview player exists (create if needed) and cancel any pending dispose.
  void _initPreviewPlayerIfNeeded() {
    _previewDisposeTimer?.cancel();
    _cancelSmartWarmUp();
    if (_previewPlayer == null) {
      _createPreviewPlayer(initialSeekMs: _dragValue);
    }
  }

  void _onDragStart([double? initialValue]) {
    _hideTimer?.cancel();
    if (!_isConfirmingSeek) {
      _wasPlayingBeforeDrag = _playing;
    } else {
      // If they start dragging again while confirming, just resume dragging
      setState(() {
        _isConfirmingSeek = false;
      });
    }
    // Note: We DO NOT pause the player here. If it's playing, it keeps playing!

    setState(() {
      _isDragging = true;
      // Use the actual touch position if provided, otherwise fallback to current position
      _dragValue = initialValue ?? _position.inMilliseconds.toDouble();
      // Do NOT reset _isPreviewReady here — if the player was pre-warmed,
      // it's already ready and the width listener won't fire again.
      // _isPreviewReady is reset when the player is disposed in _schedulePreviewDispose.
    });
    _initPreviewPlayerIfNeeded();
    // If preview player is already warmed up and ready, immediately seek to the
    // touched position and start playing forward (理解 A：可播放预览)。
    if (_previewPlayer != null && _isPreviewReady) {
      _seekPreview(_dragValue);
    }
  }

  void _onDragUpdate(double milliseconds) {
    final double screenWidth = MediaQuery.of(context).size.width;
    // 粗略估算底部进度条的物理长度（减去两边的时间文本和内边距）
    final double trackWidth = (screenWidth - 132) > 100 ? (screenWidth - 132) : 100;
    final double msPerPixel = _duration.inMilliseconds / trackWidth;
    
    // 触摸抖动死区（迟滞）：以上次接受的位置为中心、半径 _kSliderDeadbandPx 个物理像素。
    // 半径远大于触摸抖动幅度，手指压住时的"微小前进后退"会被整体吸收，不更新进度/预览；
    // 只有朝一个方向真正推过该距离才会突破死区开始跟手（同时充当起步 slop）。
    double thresholdMs = msPerPixel * _kSliderDeadbandPx;
    if (thresholdMs < _kSliderDeadbandFloorMs) thresholdMs = _kSliderDeadbandFloorMs;

    // 物理位移小于死区半径，直接丢弃，彻底过滤静止抖动与误触
    if ((milliseconds - _dragValue).abs() < thresholdMs) return;

    setState(() {
      _dragValue = milliseconds.clamp(0.0, _duration.inMilliseconds.toDouble());
    });
    
    // 少 seek 多播放：预览正在向前连续播放，仅当手指移动超过阈值才重新定位。
    // 首次定位或大幅跳转（>3s）立即 seek，保证快速看到目标画面。
    if (_previewController != null && _isPreviewReady) {
      if (_previewSeekTarget < 0 ||
          (_dragValue - _previewSeekTarget).abs() > 3000) {
        _seekPreview(_dragValue);
      }

      // 拖尾（Trailing Edge）：手指停下后若与当前定位仍有较大偏差，对齐一次，
      // 确保预览最终落在用户真正想看的段落。
      _seekDebounceTimer?.cancel();
      _seekDebounceTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted &&
            _isDragging &&
            _isPreviewReady &&
            (_dragValue - _previewSeekTarget).abs() > 1500) {
          _seekPreview(_dragValue);
        }
      });
    }
  }

  void _onDragEnd() {
    setState(() {
      _isDragging = false;
      _isConfirmingSeek = true;
    });
    // 停止预览的向前播放，定格在确认帧，同时释放带宽 / 解码资源。
    // 不改变主播放器的播放状态，等待用户确认或取消。
    _seekDebounceTimer?.cancel();
    _previewPlayer?.pause();
  }

  void _confirmSeek() {
    setState(() {
      _isConfirmingSeek = false;
    });
    player.seek(Duration(milliseconds: _dragValue.toInt()));
    if (!_wasPlayingBeforeDrag) {
      player.pause(); // Force mpv to stay paused if it wasn't playing before
    }
    _schedulePreviewDispose();
    _startHideTimer();
  }

  void _cancelSeek() {
    setState(() {
      _isConfirmingSeek = false;
    });
    // Restore the preview window timeout, no seeking is done.
    _schedulePreviewDispose();
    _startHideTimer();
  }

  void _schedulePreviewDispose() {
    _previewDisposeTimer?.cancel();
    // 移动端：10 秒后回收预览播放器释放解码器资源；桌面端：30 秒（保留快速再次拖动体验）
    final timeout = (Platform.isAndroid || Platform.isIOS)
        ? const Duration(seconds: 10)
        : const Duration(seconds: 30);
    _previewDisposeTimer = Timer(timeout, () {
      if (mounted && !_isDragging && !_isConfirmingSeek) {
        _previewPlayer?.dispose();
        _previewPlayer = null;
        _previewController = null;
        _isPreviewReady = false;
        _previewSeekTarget = -1;
        _warmUpInProgress = false;
        setState(() {});
        if (_playing && !_isBuffering && _previewIsBackupLine) {
          _scheduleSmartWarmUp(const Duration(seconds: 15));
        }
      }
    });
  }

  void _onDoubleTapDown(TapDownDetails details, double screenWidth) {
    if (_isConfirmingSeek) {
      _cancelSeek();
      return;
    }
    if (!widget.state.isFullscreen()) return; // Disable +/- 10s gesture in portrait mode
    
    if (details.globalPosition.dx < screenWidth / 2) {
      // Seek backward 10s
      final target = _position - const Duration(seconds: 10);
      player.seek(target < Duration.zero ? Duration.zero : target);
      _showActionIndicator(Icons.replay_10, '-10s');
    } else {
      // Seek forward 10s
      final target = _position + const Duration(seconds: 10);
      player.seek(target > _duration ? _duration : target);
      _showActionIndicator(Icons.forward_10, '+10s');
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        // 2. Gesture Detector for surface interaction
        Positioned.fill(
          child: GestureDetector(
            onTap: _toggleControls,
            onDoubleTapDown: (details) => _onDoubleTapDown(details, screenWidth),
            onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, screenWidth),
            // 视频画面横滑已移除：预览只由底部进度条拖拽触发（避免画面误滑触发 seek/预览）。
            behavior: HitTestBehavior.opaque,
          ),
        ),

        // 3. Center Action Indicator (Volume/Brightness/Seek popup)
        if (_showIndicator)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_indicatorIcon != null) Icon(_indicatorIcon, color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    _indicatorText,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

        // 3.5 Buffering Overlay — shown when player is buffering
        if (_isBuffering && !_isDragging)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
                if (_showWeakNetHint) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 14),
                        SizedBox(width: 6),
                        Text(
                          '网络较弱，缓冲中…',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

        // 4. Controls Overlay
        AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Stack(
              children: [
                // Top Bar (Hidden in portrait)
                if (widget.state.isFullscreen())
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 4,
                        bottom: 8,
                        left: 16,
                        right: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          if (widget.onBack != null)
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                              onPressed: widget.onBack,
                            ),
                          if (widget.title != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.title!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),

                // Center Play/Pause Buttons
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.state.isFullscreen()) ...[
                        IconButton(
                          icon: const Icon(Icons.replay_10, color: Colors.white, size: 48),
                          onPressed: () {
                            _startHideTimer();
                            final target = _position - const Duration(seconds: 10);
                            player.seek(target < Duration.zero ? Duration.zero : target);
                          },
                        ),
                        const SizedBox(width: 40),
                      ],
                      GestureDetector(
                        onTap: () {
                          if (_isConfirmingSeek) {
                            _cancelSeek();
                            return;
                          }
                          _startHideTimer();
                          player.playOrPause();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withOpacity(0.8),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Icon(
                            _playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                      if (widget.state.isFullscreen()) ...[
                        const SizedBox(width: 40),
                        IconButton(
                          icon: const Icon(Icons.forward_10, color: Colors.white, size: 48),
                          onPressed: () {
                            _startHideTimer();
                            final target = _position + const Duration(seconds: 10);
                            player.seek(target > _duration ? _duration : target);
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                // Bottom Bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                          left: 16,
                          right: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: primaryColor,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: primaryColor,
                                  trackHeight: 4.0,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                                ),
                                  child: Slider(
                                    value: ((_isDragging || _isConfirmingSeek) ? _dragValue : _position.inMilliseconds.toDouble()).clamp(0.0, _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0),
                                  min: 0.0,
                                  max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                                  onChangeStart: (val) {
                                    _onDragStart(val);
                                  },
                                  onChanged: (val) {
                                    _onDragUpdate(val);
                                  },
                                  onChangeEnd: (val) {
                                    _onDragEnd();
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              _formatDuration(_duration),
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                widget.state.isFullscreen() ? Icons.fullscreen_exit : Icons.fullscreen,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                _startHideTimer();
                                if (widget.state.isFullscreen()) {
                                  _exitFullscreen();
                                } else {
                                  _enterFullscreenWithWarmUp();
                                }
                              },
                            )
                          ],
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 4.5 Invisible Blocker Overlay (Cancels seek on tap outside)
        if (_isConfirmingSeek)
          Positioned.fill(
            child: GestureDetector(
              onTap: _cancelSeek,
              behavior: HitTestBehavior.opaque,
            ),
          ),

        // 5. Preview Window (Fullscreen Only)
        if (widget.state.isFullscreen() && (_isDragging || _isConfirmingSeek) && _previewController != null)
          Positioned(
            bottom: 80,
            left: (_dragValue / (_duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1)).clamp(0.0, 1.0) * (screenWidth - 160),
            child: Container(
              width: 160,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryColor, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _isPreviewReady 
                      ? Video(controller: _previewController!, controls: (state) => const SizedBox.shrink())
                      : Container(
                          color: Colors.black87,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Dimmed video placeholder (main player frame bleeds through slightly)
                              Center(
                                child: Icon(Icons.movie_filter_rounded, color: Colors.white.withOpacity(0.15), size: 32),
                              ),
                              // Indeterminate loading bar at the bottom
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  backgroundColor: Colors.transparent,
                                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor.withOpacity(0.6)),
                                  minHeight: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                    if (_isConfirmingSeek)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _confirmSeek,
                          child: Container(
                            color: Colors.black45,
                            child: const Center(
                              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatDuration(Duration(milliseconds: _dragValue.toInt())),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
