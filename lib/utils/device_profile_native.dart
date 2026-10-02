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
  static const constrainedFwdBytes = '10485760'; // 10 MB
  static const constrainedBackBytes = '6291456'; // 6 MB
  static const constrainedReadaheadSecs = '12';
  static const constrainedCacheSecs = '20';
  static const constrainedStreamBuffer = '524288'; // 512 KB
  static const constrainedHwdecExtraFrames = '2';

  /// Image cache caps when constrained.
  static const constrainedImageCacheCount = 50;
  static const constrainedImageCacheBytes = 48 << 20; // 48 MB

  /// Speed-test early batch size when constrained.
  static const constrainedProbeEarlyBatch = 2;

  /// Cover decode width hint (logical px) fallback when layout unknown.
  static const constrainedCoverMemWidth = 240;

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
