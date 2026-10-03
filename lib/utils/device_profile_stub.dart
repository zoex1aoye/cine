import 'package:flutter/foundation.dart';

/// Web / unsupported platforms: always normal tier.
enum DeviceProfileTier { normal, constrained }

class DeviceProfile {
  DeviceProfile._();

  static DeviceProfileTier get tier => DeviceProfileTier.normal;
  static bool get isConstrained => false;
  static int? get totalMemBytes => null;
  static int? get availMemBytes => null;

  static const constrainedFwdBytes = '8388608';
  static const constrainedBackBytes = '2097152';
  static const constrainedReadaheadSecs = '8';
  static const constrainedCacheSecs = '15';
  static const constrainedStreamBuffer = '262144';
  static const constrainedHwdecExtraFrames = '1';
  static const constrainedImageCacheCount = 30;
  static const constrainedImageCacheBytes = 24 << 20;
  static const constrainedProbeEarlyBatch = 2;
  static const constrainedCoverMemWidth = 180;

  static Future<void> ensureInitialized() async {}

  static void applyImageCacheLimits() {}

  static void trimImageCacheOnPlayerEnter() {}

  @visibleForTesting
  static void debugOverride({
    DeviceProfileTier? tier,
    int? totalMemBytes,
    bool resetInitialized = false,
  }) {}
}
