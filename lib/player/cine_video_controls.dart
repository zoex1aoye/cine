import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../utils/cine_surface.dart';
import '../utils/platform_utils.dart';
import '../utils/tv_focus.dart';

class CineVideoControls extends StatefulWidget {
  final VideoState state;
  final String? title;

  const CineVideoControls(this.state, {super.key, this.title});

  @override
  State<CineVideoControls> createState() => _CineVideoControlsState();
}

class _CineVideoControlsState extends State<CineVideoControls> {
  bool _showControls = false;
  final FocusNode _tvTransportFocus = FocusNode(debugLabel: 'tv-transport');
  bool _tvTransportLatched = false;

  /// 用户已经开始过播放后，窗口态才提供播放/暂停焦点，避免绕过详情页开播。
  bool _tvWindowPlaybackEngaged = false;
  Timer? _hideTimer;
  Timer? _indicatorTimer;

  // Main-player scrub preview
  bool _isScrubbing = false;
  Duration? _anchorPosition;
  bool? _anchorWasPlaying;

  /// Per-gesture: whether playback should resume when the thumb is released.
  /// Independent of the return-to-anchor session (which only sets [_anchorWasPlaying]
  /// on the first scrub of a tip cycle).
  bool _wasPlayingBeforeScrub = false;
  Duration _scrubTarget = Duration.zero;
  bool _showReturnTip = false;
  Timer? _returnTipTimer;
  Timer? _seekDebounceTimer;

  /// Bumps on each seek so in-flight seeks from scrub updates cannot run after end.
  int _seekEpoch = 0;

  static const _returnTipDuration = Duration(seconds: 30);
  static const _returnTipMinOffset = Duration(seconds: 5);

  // 进度条拖动死区（迟滞）半径，单位：物理像素。
  static const double _kSliderDeadbandPx = 10.0;
  static const double _kSliderDeadbandFloorMs = 1200.0;

  // Gestures
  double _brightness = 0.5;
  double _volume = 100.0;

  /// Only the outer [fraction] of screen width accepts brightness/volume drags.
  static const double _kEdgeGestureWidthFraction = 0.2;

  /// Ignore small vertical movement so taps / scrolls do not adjust levels.
  static const double _kVerticalGestureThresholdPx = 24.0;

  _VerticalGestureKind _activeVerticalGesture = _VerticalGestureKind.none;
  double _verticalDragDistancePx = 0.0;

  // Indicator State
  String _indicatorText = '';
  IconData? _indicatorIcon;
  bool _showIndicator = false;

  Player get player => widget.state.widget.controller.player;

  late StreamSubscription _playingSub;
  late StreamSubscription _positionSub;
  late StreamSubscription _durationSub;
  late StreamSubscription _volumeSub;
  late StreamSubscription _bufferingSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isBuffering = false;

  /// 缓冲满此时长后再显示速度行，避免短缓冲闪一下。
  static const _bufferSpeedRevealDelay = Duration(milliseconds: 800);
  static const _cacheSpeedPollInterval = Duration(milliseconds: 500);

  Timer? _bufferSpeedRevealTimer;
  Timer? _cacheSpeedPollTimer;
  bool _showBufferSpeed = false;

  /// 已格式化的速率（如 `1.2 MB/s`）；`null` 表示显示 —。
  String? _cacheSpeedText;

  bool get _hasAnchorSession => _anchorPosition != null;

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
      if (!mounted) return;
      setState(() {
        _playing = event;
        if (event) _tvWindowPlaybackEngaged = true;
      });
    });
    _positionSub = player.stream.position.listen((event) {
      if (mounted && !_isScrubbing) {
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
      if (event) {
        _armBufferSpeedHud();
      } else {
        _clearBufferSpeedHud();
      }
    });
  }

  @override
  void dispose() {
    _returnTipTimer?.cancel();
    _seekDebounceTimer?.cancel();
    ScreenBrightness().resetScreenBrightness();
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _bufferSpeedRevealTimer?.cancel();
    _cacheSpeedPollTimer?.cancel();
    _playingSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _volumeSub.cancel();
    _bufferingSub.cancel();
    _tvTransportFocus.dispose();
    super.dispose();
  }

  void _armBufferSpeedHud() {
    _bufferSpeedRevealTimer ??= Timer(_bufferSpeedRevealDelay, () {
      if (!mounted || !_isBuffering) return;
      setState(() => _showBufferSpeed = true);
      _startCacheSpeedPoll();
    });
  }

  void _clearBufferSpeedHud() {
    _bufferSpeedRevealTimer?.cancel();
    _bufferSpeedRevealTimer = null;
    _cacheSpeedPollTimer?.cancel();
    _cacheSpeedPollTimer = null;
    if (_showBufferSpeed || _cacheSpeedText != null) {
      setState(() {
        _showBufferSpeed = false;
        _cacheSpeedText = null;
      });
    }
  }

  void _startCacheSpeedPoll() {
    _cacheSpeedPollTimer?.cancel();
    _pollCacheSpeed();
    _cacheSpeedPollTimer = Timer.periodic(_cacheSpeedPollInterval, (_) {
      _pollCacheSpeed();
    });
  }

  Future<void> _pollCacheSpeed() async {
    if (!mounted || !_isBuffering || !_showBufferSpeed) return;
    String? formatted;
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        final raw = await platform.getProperty('cache-speed');
        final bytesPerSec = double.tryParse(raw.trim());
        if (bytesPerSec != null && bytesPerSec > 0) {
          formatted = _formatBytesPerSec(bytesPerSec);
        }
      }
    } catch (_) {
      formatted = null;
    }
    if (!mounted || !_isBuffering || !_showBufferSpeed) return;
    if (_cacheSpeedText != formatted) {
      setState(() => _cacheSpeedText = formatted);
    }
  }

  String _formatBytesPerSec(double bytesPerSec) {
    if (bytesPerSec < 1024) {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  void _toggleControls() {
    final willShow = !_showControls;
    setState(() => _showControls = willShow);
    if (willShow) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// Desktop: pointer enter / move shows chrome and (re)starts idle hide.
  void _showControlsTransiently() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideTimer();
  }

  void _hideControlsImmediate() {
    _hideTimer?.cancel();
    if (_showControls && mounted) {
      setState(() => _showControls = false);
    }
  }

  void _onSurfaceTap() {
    if (isDesktopPlatform) {
      player.playOrPause();
      return;
    }
    _toggleControls();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_isScrubbing) {
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

  void _clearAnchorSession() {
    _returnTipTimer?.cancel();
    _returnTipTimer = null;
    _anchorPosition = null;
    _anchorWasPlaying = null;
    _showReturnTip = false;
  }

  void _scheduleReturnTip() {
    final anchor = _anchorPosition;
    if (anchor == null) return;

    final offset = (_scrubTarget - anchor).abs();
    if (offset <= _returnTipMinOffset) {
      _clearAnchorSession();
      return;
    }

    _returnTipTimer?.cancel();
    setState(() => _showReturnTip = true);
    _returnTipTimer = Timer(_returnTipDuration, () {
      if (mounted) {
        setState(() => _clearAnchorSession());
      }
    });
  }

  Future<void> _seekMain(Duration target) async {
    final epoch = ++_seekEpoch;
    _scrubTarget = target;
    await player.seek(target);
    if (epoch != _seekEpoch) return;
  }

  void _debouncedSeekMain(Duration target) {
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) unawaited(_seekMain(target));
    });
  }

  void _onScrubStart(double ms) {
    _hideTimer?.cancel();
    _seekDebounceTimer?.cancel();
    // Drop any in-flight scrub seeks from a prior gesture.
    _seekEpoch++;

    // Always capture for THIS gesture (do not gate on anchor session).
    _wasPlayingBeforeScrub = _playing || player.state.playing;

    if (!_hasAnchorSession) {
      _anchorPosition = _position;
      _anchorWasPlaying = _wasPlayingBeforeScrub;
    }

    // Do not pause and do not seek on start — pause+overlapping seeks race on
    // Android media_kit and leave the player stopped after release.

    final target = Duration(
      milliseconds: ms.clamp(0.0, _duration.inMilliseconds.toDouble()).toInt(),
    );

    setState(() {
      _isScrubbing = true;
      _scrubTarget = target;
      _showControls = true; // 拖动中保持底栏，并立刻藏中心键
      if (_showReturnTip) {
        _showReturnTip = false;
        _returnTipTimer?.cancel();
        _returnTipTimer = null;
      }
    });
  }

  void _onScrubUpdate(double milliseconds) {
    final screenWidth = MediaQuery.of(context).size.width;
    final trackWidth = (screenWidth - 132) > 100 ? (screenWidth - 132) : 100;
    final msPerPixel = _duration.inMilliseconds / trackWidth;

    var thresholdMs = msPerPixel * _kSliderDeadbandPx;
    if (thresholdMs < _kSliderDeadbandFloorMs) {
      thresholdMs = _kSliderDeadbandFloorMs;
    }

    if ((milliseconds - _scrubTarget.inMilliseconds.toDouble()).abs() <
        thresholdMs) {
      return;
    }

    final clampedMs = milliseconds.clamp(
      0.0,
      _duration.inMilliseconds.toDouble(),
    );
    setState(() {
      _scrubTarget = Duration(milliseconds: clampedMs.toInt());
    });
    _debouncedSeekMain(_scrubTarget);
  }

  Future<void> _onScrubEnd() async {
    _seekDebounceTimer?.cancel();
    // Invalidate in-flight scrub seeks, then pin final position + resume.
    final target = _scrubTarget;
    // 只看本次手势捕获的播放态；_anchorWasPlaying 是“回到锚点”会话的口径，
    // 不随用户手动暂停更新，拿来判恢复会让暂停态拖动松手后意外起播。
    final shouldResume = _wasPlayingBeforeScrub;
    _wasPlayingBeforeScrub = false;

    final epoch = ++_seekEpoch;
    await player.seek(target);
    if (!mounted || epoch != _seekEpoch) return;

    if (shouldResume) {
      await player.play();
      // A seek started before this end can still complete afterward and pause
      // mpv on Android — reinforce play once shortly after.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 150), () async {
          if (!mounted || epoch != _seekEpoch) return;
          if (!player.state.playing) {
            await player.play();
            if (mounted) setState(() => _playing = true);
          }
        }),
      );
    }

    if (!mounted) return;
    setState(() {
      _position = target;
      _isScrubbing = false;
      if (shouldResume) _playing = true;
    });
    _scheduleReturnTip();
    _startHideTimer();
  }

  Future<void> _returnToAnchor() async {
    final anchor = _anchorPosition;
    if (anchor == null) return;

    _seekDebounceTimer?.cancel();
    await _seekMain(anchor);
    if (_anchorWasPlaying == true) {
      await player.play();
    } else {
      await player.pause();
    }

    if (mounted) {
      setState(() {
        _position = anchor;
        _clearAnchorSession();
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details, double screenWidth) {
    if (!widget.state.isFullscreen()) return;
    _verticalDragDistancePx = 0.0;
    _activeVerticalGesture = _verticalGestureKindForX(
      details.globalPosition.dx,
      screenWidth,
    );
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (!widget.state.isFullscreen()) return;
    if (_activeVerticalGesture == _VerticalGestureKind.none) return;

    _verticalDragDistancePx += details.delta.dy.abs();
    if (_verticalDragDistancePx < _kVerticalGestureThresholdPx) return;

    _startHideTimer();
    final dy = details.delta.dy;
    switch (_activeVerticalGesture) {
      case _VerticalGestureKind.brightness:
        setState(() {
          _brightness -= dy * 0.005;
          _brightness = _brightness.clamp(0.0, 1.0);
        });
        ScreenBrightness().setScreenBrightness(_brightness);
        _showActionIndicator(
          Icons.brightness_medium,
          '${(_brightness * 100).round()}%',
        );
      case _VerticalGestureKind.volume:
        setState(() {
          _volume -= dy * 0.5;
          _volume = _volume.clamp(0.0, 100.0);
        });
        player.setVolume(_volume);
        _showActionIndicator(
          _volume == 0 ? Icons.volume_off : Icons.volume_up,
          '${_volume.round()}%',
        );
      case _VerticalGestureKind.none:
        break;
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _activeVerticalGesture = _VerticalGestureKind.none;
    _verticalDragDistancePx = 0.0;
  }

  _VerticalGestureKind _verticalGestureKindForX(double dx, double screenWidth) {
    final edge = screenWidth * _kEdgeGestureWidthFraction;
    if (dx <= edge) return _VerticalGestureKind.brightness;
    if (dx >= screenWidth - edge) return _VerticalGestureKind.volume;
    return _VerticalGestureKind.none;
  }

  void _onDoubleTapDown(TapDownDetails details, double screenWidth) {
    if (!widget.state.isFullscreen()) return;

    if (_hasAnchorSession) _clearAnchorSession();

    if (details.globalPosition.dx < screenWidth / 2) {
      _seekBy(const Duration(seconds: -10));
    } else {
      _seekBy(const Duration(seconds: 10));
    }
  }

  void _seekBy(Duration delta) {
    final target = _position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    player.seek(clamped);
    if (delta.isNegative) {
      _showActionIndicator(Icons.replay_10, '-${delta.abs().inSeconds}s');
    } else {
      _showActionIndicator(Icons.forward_10, '+${delta.inSeconds}s');
    }
  }

  void _nudgeVolume(double delta) {
    setState(() {
      _volume = (_volume + delta).clamp(0.0, 100.0);
    });
    player.setVolume(_volume);
    _showActionIndicator(
      _volume == 0 ? Icons.volume_off : Icons.volume_up,
      '${_volume.round()}%',
    );
  }

  KeyEventResult _onTvKey(FocusNode node, KeyEvent event) {
    if (!tvTransportKeysEnabled(widget.state.isFullscreen()) ||
        event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _showControlsTransiently();
      _seekBy(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _showControlsTransiently();
      _seekBy(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _showControlsTransiently();
      _nudgeVolume(5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _showControlsTransiently();
      _nudgeVolume(-5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _showControlsTransiently();
      player.playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (widget.state.isFullscreen()) {
        widget.state.exitFullscreen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  Widget _tvRoundIcon(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  Widget _tvWindowActions() {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tvWindowPlaybackEngaged) ...[
            TvFocusable(
              onActivate: () => player.playOrPause(),
              borderRadius: 24,
              focusedScale: 1.04,
              child: _tvRoundIcon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
          ],
          TvFocusable(
            onActivate: () => widget.state.enterFullscreen(),
            borderRadius: 24,
            focusedScale: 1.04,
            child: _tvRoundIcon(Icons.fullscreen),
          ),
        ],
      ),
    );
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
    final sliderValue =
        (_isScrubbing
                ? _scrubTarget.inMilliseconds.toDouble()
                : _position.inMilliseconds.toDouble())
            .clamp(
              0.0,
              _duration.inMilliseconds.toDouble() > 0
                  ? _duration.inMilliseconds.toDouble()
                  : 1.0,
            );

    final transport = tvTransportKeysEnabled(widget.state.isFullscreen());
    if (transport && !_tvTransportLatched) {
      _tvTransportLatched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && tvTransportKeysEnabled(widget.state.isFullscreen())) {
          _tvTransportFocus.requestFocus();
        }
      });
    } else if (!transport) {
      _tvTransportLatched = false;
    }

    return Focus(
      focusNode: _tvTransportFocus,
      autofocus: transport,
      canRequestFocus: transport,
      skipTraversal: !transport,
      descendantsAreFocusable: !transport,
      onKeyEvent: _onTvKey,
      child: MouseRegion(
        onEnter: isDesktopPlatform ? (_) => _showControlsTransiently() : null,
        onHover: isDesktopPlatform ? (_) => _showControlsTransiently() : null,
        onExit: isDesktopPlatform ? (_) => _hideControlsImmediate() : null,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _onSurfaceTap,
                onDoubleTapDown: (details) =>
                    _onDoubleTapDown(details, screenWidth),
                onVerticalDragStart: (details) =>
                    _onVerticalDragStart(details, screenWidth),
                onVerticalDragUpdate: (details) =>
                    _onVerticalDragUpdate(details, screenWidth),
                onVerticalDragEnd: _onVerticalDragEnd,
                behavior: HitTestBehavior.opaque,
              ),
            ),

            if (_showIndicator)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_indicatorIcon != null)
                        Icon(_indicatorIcon, color: Colors.white, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        _indicatorText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 偏下避开中心播控；控件显示时转圈+速度不再压在播放按钮上。
            if (_isBuffering && !_isScrubbing)
              Align(
                alignment: const Alignment(0, 0.42),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white70,
                        ),
                      ),
                    ),
                    if (_showBufferSpeed) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '加载中 ${_cacheSpeedText ?? '—'}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            ExcludeFocus(
              excluding: !_showControls || transport,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Stack(
                    children: [
                      // 中间播控在下层；全屏顶栏必须更高 z-order，否则安卓上返回键点击被吞。
                      // 拖进度条时彻底去掉中心键（勿仅靠叠层遮挡）。
                      if (!_isScrubbing)
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (widget.state.isFullscreen()) ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.replay_10,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                  onPressed: () {
                                    _startHideTimer();
                                    final target =
                                        _position - const Duration(seconds: 10);
                                    player.seek(
                                      target < Duration.zero
                                          ? Duration.zero
                                          : target,
                                    );
                                  },
                                ),
                                const SizedBox(width: 40),
                              ],
                              GestureDetector(
                                onTap: () {
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
                                  icon: const Icon(
                                    Icons.forward_10,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                  onPressed: () {
                                    _startHideTimer();
                                    final target =
                                        _position + const Duration(seconds: 10);
                                    player.seek(
                                      target > _duration ? _duration : target,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),

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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isScrubbing) ...[
                                Text(
                                  _formatDuration(_scrubTarget),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Row(
                                children: [
                                  // 拖动时只保留上方大号时间，左侧不再重复同一时刻。
                                  SizedBox(
                                    width: 48,
                                    child: _isScrubbing
                                        ? const SizedBox.shrink()
                                        : Text(
                                            _formatDuration(_position),
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        activeTrackColor: primaryColor,
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: primaryColor,
                                        trackHeight: 4.0,
                                        // 关掉系统拖动气泡，避免与上方大号时间重复。
                                        showValueIndicator:
                                            ShowValueIndicator.never,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6.0,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 14.0,
                                            ),
                                      ),
                                      child: Slider(
                                        value: sliderValue,
                                        min: 0.0,
                                        max:
                                            _duration.inMilliseconds
                                                    .toDouble() >
                                                0
                                            ? _duration.inMilliseconds
                                                  .toDouble()
                                            : 1.0,
                                        onChangeStart: _onScrubStart,
                                        onChanged: _onScrubUpdate,
                                        onChangeEnd: (_) {
                                          unawaited(_onScrubEnd());
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    _formatDuration(_duration),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      widget.state.isFullscreen()
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      _startHideTimer();
                                      if (widget.state.isFullscreen()) {
                                        widget.state.exitFullscreen();
                                      } else {
                                        widget.state.enterFullscreen();
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (widget.state.isFullscreen())
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.only(
                              top: MediaQuery.of(context).padding.top + 4,
                              bottom: 8,
                              left: 8,
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
                                // 全屏返回只退内部全屏，禁止走页面级 Navigator.pop：
                                // 后者在全屏路由已卸掉后的二次触发会把 PlayerPage 一并弹出。
                                // opaque 热区避免点在图标边缘时被渐变条吞掉且无回调。
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    _startHideTimer();
                                    if (widget.state.isFullscreen()) {
                                      widget.state.exitFullscreen();
                                    }
                                  },
                                  child: const SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Icon(
                                      Icons.arrow_back_ios_new,
                                      color: Colors.white,
                                    ),
                                  ),
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
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (isTvSurface && !transport) _tvWindowActions(),

            if (_showReturnTip && _anchorPosition != null)
              Positioned(
                top: widget.state.isFullscreen()
                    ? MediaQuery.of(context).padding.top + 56
                    : 16,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _returnToAnchor,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.undo, color: primaryColor, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '回到 ${_formatDuration(_anchorPosition!)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _VerticalGestureKind { none, brightness, volume }
