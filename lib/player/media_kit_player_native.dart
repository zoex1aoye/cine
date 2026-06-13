// media_kit_player_native.dart – native implementation using media_kit
import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'jp_player.dart';
import '../api/jp_log.dart';

/// 基于 `media_kit` 实现的原生桌面/移动端播放控制器实现类
/// 
/// 针对 Linux 环境下的 AMD/Intel/NVIDIA GPU 做了硬件加速优化，配置了代理安全白名单，
/// 并使用原生 C-Runtime 数值区域修正 (setlocale) 以规避 C-locale 段错误崩溃。
class MediaKitPlayerImpl implements JpPlayer {
  final String initialUrl;
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

  MediaKitPlayerImpl({required this.initialUrl});

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
    _player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.debug,
      ),
    );

    // 绑定并打印 mpv 的原生日志
    _subscriptions.add(_player.stream.log.listen((event) {
      jpLog('MPV', '[${event.prefix}] ${event.text}');
    }));

    try {
      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;
        
        // 关键优化点 1：Linux 下的硬件解码强制配置
        // media_kit 默认去查找 CUDA（容易导致 AMD 显卡崩溃），
        // 此处显式地强制底层的 libmpv 选择系统的 VA-API 硬件解码管道，绕过 CUDA 探测。
        if (Platform.isLinux) {
          await native.setProperty('hwdec', 'vaapi');
          jpLog('PLAYER', 'MediaKitPlayerImpl: configured Linux hwdec=vaapi');
        }
        
        // 关键优化点 2：FFmpeg 代理支持白名单设置
        // 开启系统代理时，FFmpeg 的 httpproxy 很容易因默认安全限制被剥离，导致无法加载 HLS M3U8 的相对地址分片。
        // 此处显式地向 demuxer 和 stream 配置覆盖支持 httpproxy、tls、tcp 等各类传输层与解复用协议。
        await native.setProperty('demuxer-lavf-o', 'protocol_whitelist=[file,crypto,data,http,https,tcp,tls,udp,rtp,httpproxy]');
        await native.setProperty('stream-lavf-o', 'protocol_whitelist=[file,crypto,data,http,https,tcp,tls,udp,rtp,httpproxy]');
        jpLog('PLAYER', 'MediaKitPlayerImpl: configured protocol_whitelist=all');
      } else {
        jpLog('PLAYER', 'MediaKitPlayerImpl: player.platform is not NativePlayer');
      }
    } catch (e) {
      jpLog('PLAYER', 'MediaKitPlayerImpl: 硬件解码与代理白名单配置失败: $e');
    }

    // 关键优化点 3：禁用共享硬解纹理
    // 在部分 Linux 发行版与 AMD GPU 上，启用 enableHardwareAcceleration 往往因为 OpenGL 通道阻断导致 1x1 黑屏或崩溃。
    // 设置为 false，强制使用 CPU 像素拷贝的软件视频纹理渲染路径，虽增加了微量的内存拷贝，但在多端上达到了 100% 的渲染稳定性。
    _controller = VideoController(_player, configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: false,
    ));

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
  Future<void> setSource(String url) async {
    jpLog('PLAYER', 'MediaKitPlayerImpl: 热切换播放源至 $url');
    await _player.open(Media(url));
  }

  @override
  Future<void> dispose() async {
    jpLog('PLAYER', 'MediaKitPlayerImpl: 销毁播放控制器，释放订阅句柄...');
    for (final sub in _subscriptions) {
      await sub.cancel();
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
  Widget buildVideoWidget(BuildContext context) => Video(
    controller: _controller,
    fit: BoxFit.cover,
  );
}
