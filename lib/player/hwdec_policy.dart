import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

/// Android hwdec 能力探测、用户解码偏好、硬解失败日志特征。
///
/// 回退是否已消耗等「每个播放器实例」的状态不放这里，见 `MediaKitPlayerImpl`。
class HwdecPolicy {
  HwdecPolicy._();

  static const _channel = MethodChannel('com.example.cine/device');
  static const _prefKey = 'prefer_soft_decode';

  static bool? _h264Hw;
  static bool? _hevcHw;
  static bool _probed = false;
  static Future<void>? _probing;

  static bool? get probedH264 => _h264Hw;
  static bool? get probedHevc => _hevcHw;

  /// 探测前、探测失败、探测结果缺失时都按「有硬解」处理，由看门狗兜底。
  static bool get hasAnyHardwareVideo {
    if (!_probed || (_h264Hw == null && _hevcHw == null)) return true;
    return (_h264Hw == true) || (_hevcHw == true);
  }

  /// 并发安全：多个播放器同时初始化时共享同一次探测。
  static Future<void> ensureProbed() => _probing ??= _probe();

  static Future<void> _probe() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('hasHardwareVideoDecoder');
      if (raw != null) {
        _h264Hw = raw['h264'] as bool? ?? false;
        _hevcHw = raw['hevc'] as bool? ?? false;
      }
    } catch (_) {
      // 非 Android 或 channel 缺失：保持乐观默认。
    } finally {
      _probed = true;
    }
  }

  /// 初始 mpv `hwdec` 值（不含用户偏好）。
  static String initialHwdecProperty() {
    if (!hasAnyHardwareVideo) return 'no';
    return 'amediacodec,mediacodec';
  }

  /// 用户是否手动选择过软解（持久化在 config box）。
  static bool get userPrefersSoft {
    try {
      if (!Hive.isBoxOpen('config')) return false;
      return Hive.box<String>('config').get(_prefKey) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setUserPrefersSoft(bool value) async {
    try {
      if (!Hive.isBoxOpen('config')) return;
      final box = Hive.box<String>('config');
      if (value) {
        await box.put(_prefKey, '1');
      } else {
        await box.delete(_prefKey);
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void debugReset({
    bool? h264,
    bool? hevc,
    bool probed = true,
  }) {
    _probed = probed;
    _h264Hw = h264;
    _hevcHw = hevc;
    _probing = null;
  }
}

/// mpv 日志中「硬解初始化/运行期失败」的特征（已转小写）。
///
/// 刻意不匹配泛化的 `mediacodec` + `error`：HLS 中单个坏包的
/// `error while decoding` 之类日志很常见，不应触发整条流重开。
bool looksLikeHwdecFailure(String lowerCasedText) {
  final text = lowerCasedText;
  return text.contains('could not open hwdec') ||
      text.contains('failed to create hwdec') ||
      text.contains('error opening video hwdec') ||
      text.contains('failed to initialize video decoder') ||
      text.contains('dequeue output buffer') ||
      text.contains('omx error') ||
      text.contains('c2 error') ||
      text.contains('amediaerror') ||
      text.contains('surface abandoned') ||
      text.contains('surface invalid') ||
      text.contains('surface lost') ||
      (text.contains('hwdec') && text.contains('fallback to software')) ||
      (text.contains('mediacodec') && text.contains('failed'));
}
