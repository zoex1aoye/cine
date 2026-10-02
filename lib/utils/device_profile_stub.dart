import 'package:flutter/foundation.dart';

/// Web / unsupported platforms: always normal tier.
enum DeviceProfileTier { normal, constrained }

class DeviceProfile {
  DeviceProfile._();

  static DeviceProfileTier get tier => DeviceProfileTier.normal;
  static bool get isConstrained => false;
  static int? get totalMemBytes => null;
  static int? get availMemBytes => null;

  static const constrainedFwdBytes = '10485760';
  static const constrainedBackBytes = '6291456';
  static const constrainedReadaheadSecs = '12';
  static const constrainedCacheSecs = '20';
  static const constrainedStreamBuffer = '524288';
  static const constrainedHwdecExtraFrames = '2';
  static const constrainedImageCacheCount = 50;
  static const constrainedImageCacheBytes = 48 << 20;
  static const constrainedProbeEarlyBatch = 2;
  static const constrainedCoverMemWidth = 240;

  static Future<void> ensureInitialized() async {}

  static void applyImageCacheLimits() {}

  @visibleForTesting
  static void debugOverride({
    DeviceProfileTier? tier,
    int? totalMemBytes,
    bool resetInitialized = false,
  }) {}
}
