import 'package:flutter/foundation.dart';

import 'device_budget.dart';

export 'device_budget.dart';

/// Web / unsupported platforms: always normal tier.
class DeviceProfile {
  DeviceProfile._();

  static DeviceProfileTier get tier => DeviceProfileTier.normal;
  static bool get isConstrained => false;
  static bool get isUltra => false;
  static DeviceBudget get budget => DeviceBudget.normal;
  static int? get totalMemBytes => null;
  static int? get availMemBytes => null;

  static const constrainedProbeEarlyBatch = 2;

  static Future<void> ensureInitialized() async {}

  static void applyImageCacheLimits() {}

  static void trimImageCacheOnPlayerEnter() {}

  static void handleTrimMemory(int level) {}

  static void handleLowMemory() {}

  @visibleForTesting
  static void debugOverride({
    DeviceProfileTier? tier,
    int? totalMemBytes,
    bool resetInitialized = false,
  }) {}
}
