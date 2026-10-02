import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android hwdec probe + one-shot soft-decode fallback state.
class HwdecPolicy {
  HwdecPolicy._();

  static const _channel = MethodChannel('com.example.cine/device');

  static bool? _h264Hw;
  static bool? _hevcHw;
  static bool _probed = false;
  static bool _softFallbackUsed = false;

  static bool get softFallbackUsed => _softFallbackUsed;
  static bool? get probedH264 => _h264Hw;
  static bool? get probedHevc => _hevcHw;

  /// True if at least one common video MIME has a hardware decoder.
  static bool get hasAnyHardwareVideo {
    if (!_probed) return true; // optimistic until probed
    return (_h264Hw == true) || (_hevcHw == true);
  }

  static Future<void> ensureProbed() async {
    if (_probed) return;
    _probed = true;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('hasHardwareVideoDecoder');
      if (raw != null) {
        _h264Hw = raw['h264'] as bool? ?? false;
        _hevcHw = raw['hevc'] as bool? ?? false;
      }
    } catch (_) {
      // Non-Android or channel missing: leave optimistic defaults.
      _h264Hw = true;
      _hevcHw = true;
    }
  }

  /// Initial mpv `hwdec` value for Android.
  static String initialHwdecProperty() {
    if (!hasAnyHardwareVideo) return 'no';
    return 'amediacodec,mediacodec';
  }

  /// Mark that soft fallback reopen has been consumed (max once per video).
  /// 每装载一条新视频源时重置：单条视频内仍限一次（防止日志反复触发回退），
  /// 但不会让后续视频因回退额度被上一条耗尽而黑屏。
  static bool tryConsumeSoftFallback() {
    if (_softFallbackUsed) return false;
    _softFallbackUsed = true;
    return true;
  }

  /// Re-arm the one-shot soft fallback for a newly loaded video source.
  static void resetSoftFallback() {
    _softFallbackUsed = false;
  }

  @visibleForTesting
  static void debugReset({
    bool? h264,
    bool? hevc,
    bool probed = true,
    bool softUsed = false,
  }) {
    _probed = probed;
    _h264Hw = h264;
    _hevcHw = hevc;
    _softFallbackUsed = softUsed;
  }
}
