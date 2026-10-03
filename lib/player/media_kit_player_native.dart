// media_kit_player_native.dart – native implementation using media_kit
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'jp_player.dart';
import '../api/jp_log.dart';
import '../utils/device_profile.dart';
import 'cine_video_controls.dart';
import 'hwdec_policy.dart';
import 'hwdec_watchdog.dart';
import 'native_fullscreen_ownership.dart';
import 'playback_open_gate.dart';

/// 基于 `media_kit` 实现的原生桌面/移动端播放控制器实现类
///
/// 针对 Linux 环境下的 AMD/Intel/NVIDIA GPU 做了硬件加速优化，配置了代理安全白名单，
/// 并使用原生 C-Runtime 数值区域修正 (setlocale) 以规避 C-locale 段错误崩溃。
class MediaKitPlayerImpl implements JpPlayer {
  final String initialUrl;
  final bool isShort;
  late final Player _player;
  late final VideoController _controller;
  late String _currentUrl;
  bool _decodeReopenInFlight = false;

  /// 本条视频源是否已消耗过「自动回退软解」额度（按实例、按源重置）。
  bool _softFallbackUsed = false;

  /// 用户手动选择软解（含持久化偏好）。换集不会恢复硬解。
  bool _userForcedSoft = false;

  /// 因硬解失败自动退到软解。换集时会重新尝试硬解。
  bool _autoFellBack = false;

  /// 上次 reopen 用 `start` 属性定位后，下次 open 前要清回 0。
  bool _startOverridden = false;

  /// 这次系统全屏是播放器自己打开的。用户先开的 macOS 全屏不算。
  bool _ownsNativeFullscreen = false;

  static const _videoChannel = MethodChannel('com.alexmercerind/media_kit_video');
  static const _windowChannel = MethodChannel('cine/macos_window');

  /// 首次 open 的完成信号：日志触发的软解回退必须等它结束后再 reopen，
  /// 禁止与 initialize() 进行中的 open 并发（双重重载/状态不一致）。
  Completer<void>? _initialOpenDone;

  // 状态变更的可观察对象 ValueNotifier
  final ValueNotifier<bool> _isInitialized = ValueNotifier(false);
  final ValueNotifier<bool> _isPlaying = ValueNotifier(false);
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _isBuffering = ValueNotifier(false);
  final ValueNotifier<int?> _videoWidth = ValueNotifier(null);
  final ValueNotifier<int?> _videoHeight = ValueNotifier(null);
  final ValueNotifier<bool> _isHardwareDecode = ValueNotifier(true);

  final PlaybackOpenGate _openGate = PlaybackOpenGate();

  late final HwdecWatchdog _watchdog = HwdecWatchdog(
    hasRenderedFrame: _probeRenderedFrame,
    onStall: () {
      jpLog('PLAYER', 'Android 硬解假死看门狗触发 → 自动回退软解');
      unawaited(_fallbackToSoftwareDecode());
    },
  );

  final List<StreamSubscription> _subscriptions = [];

  MediaKitPlayerImpl({required this.initialUrl, this.isShort = false})
    : _currentUrl = initialUrl;

  @override
  ValueNotifier<bool> get isInitializedNotifier => _isInitialized;

  @override
  ValueNotifier<bool> get isPlayingNotifier => _isPlaying;

  @override
  ValueNotifier<Duration> get positionNotifier => _position;

  @override
  ValueNotifier<Duration> get durationNotifier => _duration;

  @override
  ValueNotifier<bool> get isBufferingNotifier => _isBuffering;

  @override
  ValueNotifier<int?> get videoWidthNotifier => _videoWidth;

  @override
  ValueNotifier<int?> get videoHeightNotifier => _videoHeight;

  @override
  ValueNotifier<bool> get isHardwareDecodeNotifier => _isHardwareDecode;

  @override
  bool get supportsDecodeToggle => Platform.isAndroid;

  @override
  Future<void> initialize() async {
    jpLog('PLAYER', 'MediaKitPlayerImpl: 初始化原生内核中...');
    _initialOpenDone = Completer<void>();
    // release 保持 warn，避免每条日志都过一遍 Dart 侧字符串匹配。
    // 仅 Android debug 提高到 info，便于看 decoder 协商。
    _player = Player(
      configuration: PlayerConfiguration(
        logLevel:
            (Platform.isAndroid && kDebugMode)
                ? MPVLogLevel.info
                : MPVLogLevel.warn,
      ),
    );

    // 仅在 debug 模式下挂载硬解检测日志（release build 完全跳过，zero overhead）
    assert(() {
      _subscriptions.add(
        _player.stream.log.listen((event) {
          jpLog('MPV', '[${event.prefix}] ${event.text}');
          final text = event.text.toLowerCase();
          if (text.contains('hwdec') ||
              text.contains('hardware') ||
              text.contains('videotoolbox') ||
              text.contains('vaapi') ||
              text.contains('mediacodec') ||
              text.contains('using decoder')) {
            final isHwDec =
                text.contains('hardware') ||
                text.contains('videotoolbox') ||
                text.contains('vaapi') ||
                text.contains('cuda') ||
                text.contains('nvdec') ||
                text.contains('d3d11va') ||
                text.contains('mediacodec') ||
                text.contains('amediacodec');
            jpLog('PLAYER', '解码方式: ${isHwDec ? "硬解 ✅" : "软解"}');
          }
        }),
      );
      return true;
    }());

    try {
      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;

        // 按平台 + DeviceProfile 区分缓冲区：受限档（投影/1GB 机）显著收缩，避免 demux 吃光 RAM
        final isMobile = Platform.isAndroid || Platform.isIOS;
        final constrained = DeviceProfile.isConstrained;
        final String fwdBytes;
        final String backBytes;
        final String readaheadSecs;
        final String cacheSecs;
        final String streamBuffer;
        if (constrained) {
          final b = DeviceProfile.budget;
          fwdBytes = b.demuxFwdBytes;
          backBytes = b.demuxBackBytes;
          readaheadSecs = b.readaheadSecs;
          cacheSecs = b.cacheSecs;
          streamBuffer = b.streamBuffer;
        } else if (isMobile) {
          // 移动端: 前向 32MB + 后向 24MB
          fwdBytes = '33554432';
          backBytes = '25165824';
          readaheadSecs = '25';
          cacheSecs = '45';
          streamBuffer = '1048576';
        } else {
          // 桌面端: 前向 48MB + 后向 24MB（充分保障 1080P/4K HLS 预读与秒级 Seek，同时大幅减轻 RAM 驻留）
          fwdBytes = '50331648';
          backBytes = '25165824';
          readaheadSecs = '25';
          cacheSecs = '40';
          streamBuffer = '2097152';
        }

        await native.setProperty('cache', 'yes');
        await native.setProperty('cache-secs', cacheSecs);
        await native.setProperty('demuxer-readahead-secs', readaheadSecs);
        await native.setProperty('demuxer-max-bytes', fwdBytes);
        await native.setProperty('demuxer-max-back-bytes', backBytes);
        // 已下载分片保留在内存，减少 HLS 反复拉同一 TS 分片
        await native.setProperty('demuxer-seekable-cache', 'yes');
        // 解码帧消费后尽早释放 packet 内存，防止 RAM 持续虚高
        await native.setProperty('demuxer-donate-buffer', 'yes');

        // 启动缓冲 — 播放前先缓存一段数据，避免开场卡顿（cache-pause-wait 已在下方统一设置）
        await native.setProperty('cache-pause-initial', 'yes');

        // 流探测加速 — probesize 保持默认 5MB，不额外放大（放大只会延迟打开速度）
        // analyzeduration 适当缩短以加快流元数据解析
        await native.setProperty(
          'demuxer-lavf-probesize',
          '5000000',
        ); // 5 MB (default)
        await native.setProperty(
          'demuxer-lavf-analyzeduration',
          isMobile ? '3' : '5',
        );

        // 解码线程优化 — 自动检测 CPU 核心数并启用多线程解码
        await native.setProperty('vd-lavc-threads', '0');
        // 软解快速模式：优化非关键去块滤波，显著降低 CPU 负载且视觉无损
        await native.setProperty('vd-lavc-fast', 'yes');
        // 直接渲染：减少解码器到渲染器的内存拷贝
        await native.setProperty('vd-lavc-dr', 'yes');
        // Seek 时允许丢帧以加速定位
        await native.setProperty('hr-seek-framedrop', 'yes');

        // 强制可 seek — 对 HLS 等流式协议强制启用 seek 支持
        await native.setProperty('force-seekable', 'yes');

        // FFmpeg 协议白名单：允许 HLS M3U8 相对地址分片加载
        await native.setProperty(
          'demuxer-lavf-o',
          'protocol_whitelist=[file,crypto,data,http,https,tcp,tls,udp,rtp,httpproxy]',
        );

        // HLS 并行分片下载（http_multiple=1）：
        // FFmpeg HLS demuxer 原生支持多连接并发拉取 TS/fMP4 分片，
        // 当一个分片下载时同步预取下一分片，吞吐量提升 1.5~2x（尤其高延迟环境）。
        // 作为独立 setProperty 调用，MPV dict 选项会合并而非覆盖，与 protocol_whitelist 互不干扰。
        await native.setProperty('demuxer-lavf-o', 'http_multiple=1');

        // 禁用 ICY 元数据（视频流不需要，避免协议协商额外开销）
        await native.setProperty('demuxer-lavf-o', 'icy=0');

        // HTTP 自动重连（stream-lavf-o 用于底层 stream/协议层，与 demuxer-lavf-o 的
        // protocol_whitelist 括号语法独立，避免解析冲突）
        // reconnect_delay_max=4: 最多等 4 秒后重试，兼顾弱网与等待体验
        await native.setProperty(
          'stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_delay_max=4,reconnect_on_network_error=1',
        );

        // 流底层 I/O 读缓冲（stream-buffer-size）
        await native.setProperty('stream-buffer-size', streamBuffer);

        // demuxer 独立线程（通常默认开启，但显式声明确保所有平台行为一致）：
        // 解复用(I/O) 和解码(CPU) 各占一个线程，两者并行流水线化，
        // 消除 I/O 等待造成的解码器饥饿（decode stall）。
        await native.setProperty('demuxer-thread', 'yes');

        // 网络超时：10 秒无响应即触发重连，而非无限等待（MPV 默认 60s 会让用户以为死机）
        await native.setProperty('network-timeout', '10');

        // 弱网缓冲策略：缓冲耗尽后等积累足够数据再恢复，防止 start-stop-start 反复卡顿
        await native.setProperty('cache-pause-wait', '5');

        jpLog(
          'PLAYER',
          'MediaKitPlayerImpl: buffer/protocol configured '
              '(mobile=$isMobile constrained=$constrained)',
        );
      } else {
        jpLog(
          'PLAYER',
          'MediaKitPlayerImpl: player.platform is not NativePlayer',
        );
      }
    } catch (e) {
      jpLog('PLAYER', 'MediaKitPlayerImpl: 代理白名单与缓冲优化配置失败: $e');
    }

    // 按平台配置渲染路径
    // macOS/iOS: Metal 纹理共享 | Windows: D3D11 纹理共享 | Android: Surface 纹理共享
    // Linux: 禁用硬解纹理（部分 AMD/Intel GPU 会黑屏/崩溃，强制走 CPU 像素拷贝保稳）
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration:
            Platform.isMacOS ||
            Platform.isIOS ||
            Platform.isWindows ||
            Platform.isAndroid,
      ),
    );

    // hwdec 必须在 VideoController 创建之后设置，否则会被内部初始化覆盖
    try {
      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;
        if (Platform.isMacOS || Platform.isIOS) {
          await native.setProperty('hwdec', 'videotoolbox');
        } else if (Platform.isWindows) {
          await native.setProperty('hwdec', 'd3d11va');
        } else if (Platform.isAndroid) {
          await HwdecPolicy.ensureProbed();
          _userForcedSoft = HwdecPolicy.userPrefersSoft;
          final hwdec =
              _userForcedSoft ? 'no' : HwdecPolicy.initialHwdecProperty();
          await native.setProperty('hwdec', hwdec);
          await _applyDecodeTuning(native, hardware: hwdec != 'no');
          _isHardwareDecode.value = hwdec != 'no';
          _watchdog.setEnabled(_isHardwareDecode.value);
          jpLog(
            'PLAYER',
            'Android hwdec initial=$hwdec userSoft=$_userForcedSoft '
                '(hasHw=${HwdecPolicy.hasAnyHardwareVideo} '
                'h264=${HwdecPolicy.probedH264} hevc=${HwdecPolicy.probedHevc})',
          );
        } else if (Platform.isLinux) {
          // vaapi-copy：用 VAAPI 在 GPU 上解码，然后主动将帧数据拷贝到 CPU 内存。
          // 与 enableHardwareAcceleration=false 的像素拷贝渲染路径兼容，
          // 无需 VAAPI-OpenGL EGL 互操作（规避 AMD/Intel 驱动黑屏/崩溃）。
          // 相比纯软解仍省约 40-60% CPU，decode 全程在 GPU 完成。
          await native.setProperty('hwdec', 'vaapi-copy');
        }

        // hwdec-codecs: 告知 MPV 对哪些编码格式尝试硬解。
        // 不设置时 MPV 默认仅覆盖 h264/hevc/vc1/wmv3/mpeg2，
        // VP9（B站、YouTube）和 AV1（新一代流媒体）会直接落到软解，
        // 在移动端造成不必要的高 CPU 占用和功耗。
        await native.setProperty(
          'hwdec-codecs',
          'h264,hevc,vp8,vp9,av1,mpeg4,mpeg2video,vc1,wmv3',
        );

        // hwdec-extra-frames 只对预分配表面的 API（d3d11va/vaapi）有意义。
        // MediaCodec 不受影响；仍按内存档给出较小值。
        await native.setProperty(
          'hwdec-extra-frames',
          DeviceProfile.budget.hwdecExtraFrames,
        );

        jpLog(
          'PLAYER',
          'MediaKitPlayerImpl: hwdec configured for ${Platform.operatingSystem}',
        );
      }
    } catch (e) {
      jpLog('PLAYER', 'MediaKitPlayerImpl: hwdec 配置失败: $e');
    }

    // 订阅播放状态流
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        _isPlaying.value = playing;
        _watchdog.setPlaying(playing);
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((pos) {
        _position.value = pos;
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        _duration.value = dur;
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((buf) {
        _isBuffering.value = buf;
        _watchdog.setBuffering(buf);
      }),
    );
    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        _watchdog.setHasVideoTrack(tracks.video.any(_isRealVideoTrack));
      }),
    );
    _subscriptions.add(
      _player.stream.width.listen((w) {
        // 宽度可能来自封装信息，不能当成已经出帧。看门狗只信 estimated-vf-fps。
        _videoWidth.value = w;
      }),
    );
    _subscriptions.add(
      _player.stream.height.listen((h) {
        _videoHeight.value = h;
      }),
    );

    // Android：硬解生效期间，日志命中失败特征 → 本源最多自动 reopen 软解一次
    if (Platform.isAndroid) {
      _subscriptions.add(
        _player.stream.log.listen((event) {
          if (!_isHardwareDecode.value) return;
          final text = event.text.toLowerCase();
          if (looksLikeHwdecFailure(text)) {
            jpLog('MPV', '[${event.prefix}] ${event.text}');
            unawaited(_fallbackToSoftwareDecode());
          }
        }),
      );
    }

    // 打开视频源
    try {
      await _player.open(Media(_currentUrl));
    } finally {
      _initialOpenDone?.complete();
    }
    _isInitialized.value = true;
    jpLog('PLAYER', 'MediaKitPlayerImpl: 播放源装载成功');
    if (Platform.isAndroid) {
      unawaited(_logAndroidDecoderState('after-open'));
      // 首帧/硬解协商常在 open 后异步完成，再采一次
      Future<void>.delayed(const Duration(seconds: 2), () {
        unawaited(_logAndroidDecoderState('t+2s'));
      });
    }
  }

  Future<void> _logAndroidDecoderState(String phase) async {
    try {
      if (_player.platform is! NativePlayer) return;
      final native = _player.platform as NativePlayer;
      final hwdec = await native.getProperty('hwdec');
      final hwdecCurrent = await native.getProperty('hwdec-current');
      final decoder = await native.getProperty('current-decoder');
      final vo = await native.getProperty('current-vo');
      jpLog(
        'PLAYER',
        'decoder[$phase] hwdec=$hwdec hwdec-current=$hwdecCurrent '
            'current-decoder=$decoder vo=$vo '
            'probe hw=${HwdecPolicy.hasAnyHardwareVideo} '
            'softFallbackUsed=$_softFallbackUsed',
      );
    } catch (e) {
      jpLog('PLAYER', 'decoder[$phase] probe failed: $e');
    }
  }

  static bool _isRealVideoTrack(VideoTrack t) =>
      t.id != 'auto' && t.id != 'no' && t.image != true && t.albumart != true;

  /// 看门狗到点时实测：解码器是否已有帧输出。
  /// `estimated-vf-fps` 在没有任何帧通过滤镜链时为空。
  Future<bool?> _probeRenderedFrame() async {
    if (_player.platform is! NativePlayer) return null;
    try {
      final raw = await (_player.platform as NativePlayer).getProperty(
        'estimated-vf-fps',
      );
      if (raw.isEmpty) return false;
      final fps = double.tryParse(raw);
      if (fps == null) return null;
      return fps > 0;
    } catch (_) {
      return null;
    }
  }

  /// 软解降载：ultra 跳过非参考帧滤波，constrained 跳过非关键帧；硬解恢复默认。
  Future<void> _applyDecodeTuning(
    NativePlayer native, {
    required bool hardware,
  }) async {
    final String skip;
    if (hardware) {
      skip = 'default';
    } else if (DeviceProfile.isUltra) {
      skip = 'nonref';
    } else if (DeviceProfile.isConstrained) {
      skip = 'nonkey';
    } else {
      skip = 'default';
    }
    await native.setProperty('vd-lavc-skiploopfilter', skip);
    if (!hardware) {
      await native.setProperty('vd-lavc-fast', 'yes');
    }
  }

  /// 切换解码模式并重开 [url]，保留进度与暂停态。必须在 [_openGate] 里调用。
  Future<void> _reopenWithDecode({
    required bool hardware,
    required String url,
  }) async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    final pos = _player.state.position;
    final wasPlaying = _player.state.playing;

    _watchdog.setEnabled(false);
    await native.setProperty(
      'hwdec',
      hardware ? HwdecPolicy.initialHwdecProperty() : 'no',
    );
    await _applyDecodeTuning(native, hardware: hardware);
    _isHardwareDecode.value = hardware;

    if (pos > Duration.zero) {
      await native.setProperty(
        'start',
        (pos.inMilliseconds / 1000).toStringAsFixed(3),
      );
      _startOverridden = true;
    }
    _currentUrl = url;
    await _player.open(Media(url), play: wasPlaying);
  }

  Future<void> _waitInitialOpen() async {
    final initial = _initialOpenDone;
    if (initial != null && !initial.isCompleted) {
      await initial.future;
    }
  }

  Future<void> _fallbackToSoftwareDecode() async {
    if (!Platform.isAndroid || _decodeReopenInFlight) return;
    if (_softFallbackUsed || !_isHardwareDecode.value) return;
    final generation = _openGate.generation;
    final url = _currentUrl;
    _softFallbackUsed = true;
    _decodeReopenInFlight = true;
    _watchdog.setEnabled(false);
    jpLog('PLAYER', 'Android hwdec failed → reopen once with hwdec=no');
    try {
      await _openGate.run(generation, () async {
        await _waitInitialOpen();
        if (generation != _openGate.generation) return;
        _autoFellBack = true;
        await _reopenWithDecode(hardware: false, url: url);
      });
    } catch (e) {
      jpLog('PLAYER', 'soft-decode reopen failed: $e');
    } finally {
      _decodeReopenInFlight = false;
    }
  }

  @override
  Future<void> toggleDecodeMode() async {
    if (!supportsDecodeToggle || _decodeReopenInFlight) return;
    final targetHw = !_isHardwareDecode.value;
    final generation = _openGate.bump();
    _decodeReopenInFlight = true;
    jpLog('PLAYER', '用户手动切换解码模式: ${targetHw ? "硬解" : "软解"}');
    try {
      await _openGate.run(generation, () async {
        await _waitInitialOpen();
        if (generation != _openGate.generation) return;
        await HwdecPolicy.ensureProbed();
        if (targetHw && !HwdecPolicy.hasAnyHardwareVideo) {
          jpLog('PLAYER', '设备无硬件视频解码器，忽略切回硬解');
          return;
        }
        _userForcedSoft = !targetHw;
        _autoFellBack = false;
        await HwdecPolicy.setUserPrefersSoft(_userForcedSoft);
        await _reopenWithDecode(hardware: targetHw, url: _currentUrl);
      });
    } catch (e) {
      jpLog('PLAYER', '切换解码模式失败: $e');
    } finally {
      _decodeReopenInFlight = false;
    }
  }

  @override
  Future<void> play() async => await _player.play();

  @override
  Future<void> pause() async => await _player.pause();

  @override
  Future<void> seek(Duration position) async => await _player.seek(position);

  @override
  Future<void> setSource(String url, {bool autoPlay = true}) async {
    jpLog('PLAYER', 'MediaKitPlayerImpl: 热切换播放源至 $url');
    final generation = _openGate.bump();
    _softFallbackUsed = false;
    _watchdog.resetForNewSource();
    await _openGate.run(generation, () async {
      await _waitInitialOpen();
      if (generation != _openGate.generation) return;
      _currentUrl = url;
      final native = _player.platform;
      if (native is NativePlayer) {
        if (_startOverridden) {
          await native.setProperty('start', '0');
          _startOverridden = false;
        }
        if (Platform.isAndroid && _autoFellBack && !_userForcedSoft) {
          _autoFellBack = false;
          await native.setProperty('hwdec', HwdecPolicy.initialHwdecProperty());
          await _applyDecodeTuning(native, hardware: true);
          _isHardwareDecode.value = true;
        }
        _watchdog.setEnabled(Platform.isAndroid && _isHardwareDecode.value);
      }
      await _player.open(Media(url), play: autoPlay);
    });
  }

  /// 运行时动态调整 MPV 属性（用于弱网自适应，如调整 cache-pause-wait）
  Future<void> setMpvProperty(String key, String value) async {
    try {
      if (_player.platform is NativePlayer) {
        await (_player.platform as NativePlayer).setProperty(key, value);
      }
    } catch (e) {
      debugPrint('setMpvProperty($key=$value) error: $e');
    }
  }

  @override
  Future<void> dispose() async {
    jpLog('PLAYER', 'MediaKitPlayerImpl: 销毁播放控制器，释放订阅句柄...');
    _watchdog.dispose();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }

    // 只退出播放器自己打开的系统全屏。用户用 macOS 全屏（无红绿灯）时，
    // 返回播放页不能把窗口一起退出全屏。
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
        SystemChrome.setPreferredOrientations([]);
      } else if (_ownsNativeFullscreen) {
        _ownsNativeFullscreen = false;
        _videoChannel.invokeMethod('Utils.ExitNativeFullscreen');
      }
    } catch (e) {
      debugPrint('Reset fullscreen during dispose error: $e');
    }

    await _player.dispose();
    _isInitialized.dispose();
    _isPlaying.dispose();
    _position.dispose();
    _duration.dispose();
    _isBuffering.dispose();
    _videoWidth.dispose();
    _videoHeight.dispose();
    _isHardwareDecode.dispose();
  }

  Future<bool> _windowAlreadyNativeFullscreen() async {
    if (!Platform.isMacOS) return false;
    try {
      return await _windowChannel.invokeMethod<bool>('isNativeFullscreen') ??
          false;
    } catch (e) {
      debugPrint('isNativeFullscreen failed: $e');
      return false;
    }
  }

  Future<void> _enterDesktopFullscreen() async {
    final already = await _windowAlreadyNativeFullscreen();
    _ownsNativeFullscreen = playerOwnsNativeFullscreen(
      windowAlreadyFullscreen: already,
    );
    await _videoChannel.invokeMethod('Utils.EnterNativeFullscreen');
  }

  Future<void> _exitDesktopFullscreenIfOwned() async {
    if (!_ownsNativeFullscreen) return;
    _ownsNativeFullscreen = false;
    await _videoChannel.invokeMethod('Utils.ExitNativeFullscreen');
  }

  Future<void> _onEnterFullscreen() async {
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await _enterDesktopFullscreen();
        return;
      }
      if (isShort) {
        await Future.wait([
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          ),
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]),
        ]);
        return;
      }
      await defaultEnterNativeFullscreen();
    } catch (e) {
      debugPrint('Enter native fullscreen error: $e');
    }
  }

  Future<void> _onExitFullscreen() async {
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await _exitDesktopFullscreenIfOwned();
        return;
      }
      if (isShort) {
        await Future.wait([
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
          SystemChrome.setPreferredOrientations([]),
        ]);
        return;
      }
      await defaultExitNativeFullscreen();
    } catch (e) {
      debugPrint('Exit native fullscreen error: $e');
    }
  }

  @override
  Widget buildVideoWidget(BuildContext context, {String? title}) {
    final videoWidget = Video(
      controller: _controller,
      fit: BoxFit.contain,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 48),
      ),
      controls:
          isShort
              ? AdaptiveVideoControls
              : (state) => CineVideoControls(
                state,
                title: title,
                onToggleDecodeMode:
                    supportsDecodeToggle ? toggleDecodeMode : null,
                isHardwareDecodeListenable:
                    supportsDecodeToggle ? _isHardwareDecode : null,
              ),
      onEnterFullscreen: _onEnterFullscreen,
      onExitFullscreen: _onExitFullscreen,
    );

    if (isShort) {
      return MaterialVideoControlsTheme(
        normal: const MaterialVideoControlsThemeData(),
        fullscreen: const MaterialVideoControlsThemeData(
          displaySeekBar: true,
          volumeGesture: true,
          brightnessGesture: true,
          seekGesture: true,
          backdropColor: Color(0xFF000000),
        ),
        child: videoWidget,
      );
    }

    return videoWidget;
  }
}
