import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Runtime device capability tier (independent of CineSurface).
enum DeviceProfileTier { normal, constrained }

class DeviceProfile {
  DeviceProfile._();

  static const _channel = MethodChannel('com.example.cine/device');

  static DeviceProfileTier _tier = DeviceProfileTier.normal;
  static bool _initialized = false;
  static int? _totalMemBytes;
  static int? _availMemBytes;

  static DeviceProfileTier get tier => _tier;
  static bool get isConstrained => _tier == DeviceProfileTier.constrained;
  static int? get totalMemBytes => _totalMemBytes;
  static int? get availMemBytes => _availMemBytes;

  /// Constrained demux / cache budgets (mpv string property values).
  /// 针对 1GB 设备深度压缩前向与后向缓冲区，避免系统 OOM killer 击杀应用
  static const constrainedFwdBytes = '8388608'; // 8 MB
  static const constrainedBackBytes = '2097152'; // 2 MB
  static const constrainedReadaheadSecs = '8';
  static const constrainedCacheSecs = '15';
  static const constrainedStreamBuffer = '262144'; // 256 KB
  static const constrainedHwdecExtraFrames = '1';

  /// Image cache caps when constrained (1GB 级内存收紧至 30 张 / 24MB).
  static const constrainedImageCacheCount = 30;
  static const constrainedImageCacheBytes = 24 << 20; // 24 MB

  /// Speed-test early batch size when constrained.
  static const constrainedProbeEarlyBatch = 2;

  /// Cover decode width hint (logical px) fallback when layout unknown.
  static const constrainedCoverMemWidth = 180;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final raw =
          await _channel.invokeMapMethod<String, dynamic>('getMemoryInfo');
      if (raw != null) {
        _totalMemBytes = (raw['totalMem'] as num?)?.toInt();
        _availMemBytes = (raw['availMem'] as num?)?.toInt();
        final total = _totalMemBytes;
        // < 2 GiB total → constrained (typical 1GB projector class).
        if (total != null && total > 0 && total < (2 << 30)) {
          _tier = DeviceProfileTier.constrained;
        }
      }
    } catch (_) {
      // Channel missing (desktop / stub activity) → keep normal.
    }
  }

  static void applyImageCacheLimits() {
    if (!isConstrained) return;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = constrainedImageCacheCount;
    cache.maximumSizeBytes = constrainedImageCacheBytes;
  }

  /// 进入播放页等高显存/高内存消耗场景时，主动清除非必要图片缓存，为解码器腾出物理内存
  static void trimImageCacheOnPlayerEnter() {
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clearLiveImages();
      if (isConstrained) {
        cache.clear();
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void debugOverride({
    DeviceProfileTier? tier,
    int? totalMemBytes,
    bool resetInitialized = false,
  }) {
    if (resetInitialized) _initialized = false;
    if (tier != null) _tier = tier;
    if (totalMemBytes != null) _totalMemBytes = totalMemBytes;
  }
}
