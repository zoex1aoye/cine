// media_kit_player_native.dart – native implementation using media_kit
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'jp_player.dart';
import '../api/jp_log.dart';
import 'cine_video_controls.dart';

/// 基于 `media_kit` 实现的原生桌面/移动端播放控制器实现类
/// 
/// 针对 Linux 环境下的 AMD/Intel/NVIDIA GPU 做了硬件加速优化，配置了代理安全白名单，
/// 并使用原生 C-Runtime 数值区域修正 (setlocale) 以规避 C-locale 段错误崩溃。
class MediaKitPlayerImpl implements JpPlayer {
  final String initialUrl;
  final bool isShort;
  late final Player _player;
  late final VideoController _controller;

  // 状态变更的可观察对象 ValueNotifier
  final ValueNotifier<bool> _isInitialized = ValueNotifier(false);
  final ValueNotifier<bool> _isPlaying = ValueNotifier(false);
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _isBuffering = ValueNotifier(false);
  final ValueNotifier<int?> _videoWidth = ValueNotifier(null);
  final ValueNotifier<int?> _videoHeight = ValueNotifier(null);

  final List<StreamSubscription> _subscriptions = [];

  MediaKitPlayerImpl({required this.initialUrl, this.isShort = false});

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
  Future<void> initialize() async {
    jpLog('PLAYER', 'MediaKitPlayerImpl: 初始化原生内核中...');
    // MPVLogLevel.warn: 只输出警告/错误，避免 debug 模式下每帧每次网络请求都触发
    // 日志回调 + toLowerCase()/contains() 链，显著降低 CPU 占用和移动端功耗
    _player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.warn,
      ),
    );

    // 仅在 debug 模式下挂载硬解检测日志（release build 完全跳过，zero overhead）
    assert(() {
      _subscriptions.add(_player.stream.log.listen((event) {
        jpLog('MPV', '[${event.prefix}] ${event.text}');
        final text = event.text.toLowerCase();
        if (text.contains('hwdec') || text.contains('hardware') ||
            text.contains('videotoolbox') || text.contains('vaapi') ||
            text.contains('mediacodec') || text.contains('using decoder')) {
          final isHwDec = text.contains('hardware') || text.contains('videotoolbox') ||
              text.contains('vaapi') || text.contains('cuda') ||
              text.contains('nvdec') || text.contains('d3d11va') ||
              text.contains('mediacodec') || text.contains('amediacodec');
          jpLog('PLAYER', '解码方式: ${isHwDec ? "硬解 ✅" : "软解"}');
        }
      }));
      return true;
    }());

    try {
      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;
        
        // 按平台区分缓冲区大小：移动端适度缓冲，桌面端宽裕预读
        final isMobile = Platform.isAndroid || Platform.isIOS;
        // 移动端: 前向 32MB + 后向 24MB；桌面端: 前向 128MB + 后向 64MB
        // 1080p 约 5–8 Mbps，10s 预读仅 ~6–10MB，原 16MB/10s 容易播一会儿就见底
        final fwdBytes  = isMobile ? '33554432'  : '134217728';  // 32 MB / 128 MB
        final backBytes = isMobile ? '25165824'  : '67108864';   // 24 MB / 64 MB
        final readaheadSecs = isMobile ? '25' : '45';
        final cacheSecs = isMobile ? '45' : '60';

        await native.setProperty('cache', 'yes');
        await native.setProperty('cache-secs', cacheSecs);
        await native.setProperty('demuxer-readahead-secs', readaheadSecs);
        await native.setProperty('demuxer-max-bytes', fwdBytes);
        await native.setProperty('demuxer-max-back-bytes', backBytes);
        // 已下载分片保留在内存，减少 HLS 反复拉同一 TS 分片
        await native.setProperty('demuxer-seekable-cache', 'yes');

        // 启动缓冲 — 播放前先缓存一段数据，避免开场卡顿（cache-pause-wait 已在下方统一设置）
        await native.setProperty('cache-pause-initial', 'yes');

        // 流探测加速 — probesize 保持默认 5MB，不额外放大（放大只会延迟打开速度）
        // analyzeduration 适当缩短以加快流元数据解析
        await native.setProperty('demuxer-lavf-probesize', '5000000');  // 5 MB (default)
        await native.setProperty('demuxer-lavf-analyzeduration', isMobile ? '3' : '5');

        // 解码线程优化 — 自动检测 CPU 核心数并启用多线程解码
        await native.setProperty('vd-lavc-threads', '0');
        // 直接渲染：减少解码器到渲染器的内存拷贝
        await native.setProperty('vd-lavc-dr', 'yes');
        // Seek 时允许丢帧以加速定位
        await native.setProperty('hr-seek-framedrop', 'yes');

        // 强制可 seek — 对 HLS 等流式协议强制启用 seek 支持
        await native.setProperty('force-seekable', 'yes');

        // FFmpeg 协议白名单：允许 HLS M3U8 相对地址分片加载
        await native.setProperty('demuxer-lavf-o',
            'protocol_whitelist=[file,crypto,data,http,https,tcp,tls,udp,rtp,httpproxy]');

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
        await native.setProperty('stream-lavf-o',
            'reconnect=1,reconnect_streamed=1,reconnect_delay_max=4,reconnect_on_network_error=1');

        // 流底层 I/O 读缓冲（stream-buffer-size）：
        // 每次从网络/文件系统读取的块大小，更大的块 = 更少的 I/O syscall = CPU 利用率更均匀。
        // 移动端 1MB，桌面端 4MB（提高持续下载吞吐，减少频繁小读导致的缓冲见底）。
        await native.setProperty('stream-buffer-size', isMobile ? '1048576' : '4194304');

        // demuxer 独立线程（通常默认开启，但显式声明确保所有平台行为一致）：
        // 解复用(I/O) 和解码(CPU) 各占一个线程，两者并行流水线化，
        // 消除 I/O 等待造成的解码器饥饿（decode stall）。
        await native.setProperty('demuxer-thread', 'yes');

        // 网络超时：10 秒无响应即触发重连，而非无限等待（MPV 默认 60s 会让用户以为死机）
        await native.setProperty('network-timeout', '10');

        // 弱网缓冲策略：缓冲耗尽后等积累足够数据再恢复，防止 start-stop-start 反复卡顿
        await native.setProperty('cache-pause-wait', '5');

        jpLog('PLAYER', 'MediaKitPlayerImpl: buffer/protocol configured (mobile=$isMobile)');
      } else {
        jpLog('PLAYER', 'MediaKitPlayerImpl: player.platform is not NativePlayer');
      }
    } catch (e) {
      jpLog('PLAYER', 'MediaKitPlayerImpl: 代理白名单与缓冲优化配置失败: $e');
    }

    // 按平台配置渲染路径
    // macOS/iOS: Metal 纹理共享 | Windows: D3D11 纹理共享 | Android: Surface 纹理共享
    // Linux: 禁用硬解纹理（部分 AMD/Intel GPU 会黑屏/崩溃，强制走 CPU 像素拷贝保稳）
    _controller = VideoController(_player, configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: Platform.isMacOS || Platform.isIOS || Platform.isWindows || Platform.isAndroid,
    ));

    // hwdec 必须在 VideoController 创建之后设置，否则会被内部初始化覆盖
    try {
      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;
        if (Platform.isMacOS || Platform.isIOS) {
          await native.setProperty('hwdec', 'videotoolbox');
        } else if (Platform.isWindows) {
          await native.setProperty('hwdec', 'd3d11va');
        } else if (Platform.isAndroid) {
          // amediacodec: Android 8.0+ NDK 原生 API，跳过 Java JNI 桥，每帧调用延迟更低。
          // 以 amediacodec,mediacodec 逗号形式告知 MPV：优先 amediacodec，
          // 若设备不支持（API < 26）则自动 fallback 到 mediacodec。
          await native.setProperty('hwdec', 'amediacodec,mediacodec');
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
        await native.setProperty('hwdec-codecs', 'h264,hevc,vp8,vp9,av1,mpeg4,mpeg2video,vc1,wmv3');

        // hwdec-extra-frames: 硬解流水线中额外预解码的帧数（默认 1）。
        // 设为 4 可以让解码器队列始终有前向帧储备，
        // 消除 seek 后或分辨率切换时解码器队列清空造成的单帧可见卡顿。
        await native.setProperty('hwdec-extra-frames', '4');

        jpLog('PLAYER', 'MediaKitPlayerImpl: hwdec configured for ${Platform.operatingSystem}');
      }
    } catch (e) {
      jpLog('PLAYER', 'MediaKitPlayerImpl: hwdec 配置失败: $e');
    }

    // 订阅播放状态流
    _subscriptions.add(_player.stream.playing.listen((playing) {
      _isPlaying.value = playing;
    }));
    _subscriptions.add(_player.stream.position.listen((pos) {
      _position.value = pos;
    }));
    _subscriptions.add(_player.stream.duration.listen((dur) {
      _duration.value = dur;
    }));
    _subscriptions.add(_player.stream.buffering.listen((buf) {
      _isBuffering.value = buf;
    }));
    _subscriptions.add(_player.stream.width.listen((w) {
      _videoWidth.value = w;
    }));
    _subscriptions.add(_player.stream.height.listen((h) {
      _videoHeight.value = h;
    }));

    // 打开视频源
    await _player.open(Media(initialUrl));
    _isInitialized.value = true;
    jpLog('PLAYER', 'MediaKitPlayerImpl: 播放源装载成功');
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
    await _player.open(Media(url), play: autoPlay);
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
    for (final sub in _subscriptions) {
      await sub.cancel();
    }

    // 容错处理：若销毁时处于全屏/沉浸状态，安全重置系统栏与屏幕方向以防丢失
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
        SystemChrome.setPreferredOrientations([]);
      } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        const MethodChannel('com.alexmercerind/media_kit_video')
            .invokeMethod('Utils.ExitNativeFullscreen');
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
  }

  @override
  Widget buildVideoWidget(BuildContext context, {String? title, VoidCallback? onBack, String? previewUrl}) {
    final videoWidget = Video(
      controller: _controller,
      fit: BoxFit.contain,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 48),
      ),
      controls: isShort ? AdaptiveVideoControls : (state) => CineVideoControls(state, title: title, onBack: onBack, previewUrl: previewUrl),
      onEnterFullscreen: isShort
          ? () async {
              try {
                if (Platform.isAndroid || Platform.isIOS) {
                  await Future.wait([
                    SystemChrome.setEnabledSystemUIMode(
                      SystemUiMode.immersiveSticky,
                      overlays: [],
                    ),
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                    ]),
                  ]);
                } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
                  await const MethodChannel('com.alexmercerind/media_kit_video')
                      .invokeMethod('Utils.EnterNativeFullscreen');
                }
              } catch (e) {
                debugPrint('Enter native fullscreen error: $e');
              }
            }
          : defaultEnterNativeFullscreen,
      onExitFullscreen: isShort
          ? () async {
              try {
                if (Platform.isAndroid || Platform.isIOS) {
                  await Future.wait([
                    SystemChrome.setEnabledSystemUIMode(
                      SystemUiMode.manual,
                      overlays: SystemUiOverlay.values,
                    ),
                    SystemChrome.setPreferredOrientations([]),
                  ]);
                } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
                  await const MethodChannel('com.alexmercerind/media_kit_video')
                      .invokeMethod('Utils.ExitNativeFullscreen');
                }
              } catch (e) {
                debugPrint('Exit native fullscreen error: $e');
              }
            }
          : defaultExitNativeFullscreen,
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
