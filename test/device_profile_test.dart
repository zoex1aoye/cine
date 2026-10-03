import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine/utils/device_profile.dart';

void main() {
  setUp(() {
    DeviceProfile.debugOverride(
      tier: DeviceProfileTier.normal,
      totalMemBytes: null,
      resetInitialized: true,
    );
  });

  tearDown(() {
    DeviceProfile.debugOverride(
      tier: DeviceProfileTier.normal,
      totalMemBytes: null,
      resetInitialized: true,
    );
  });

  group('DeviceProfile tier and memory limits', () {
    test('default tier is normal', () {
      expect(DeviceProfile.tier, DeviceProfileTier.normal);
      expect(DeviceProfile.isConstrained, isFalse);
    });

    test('constrained tier sets correct budget constants', () {
      DeviceProfile.debugOverride(
        tier: DeviceProfileTier.constrained,
        totalMemBytes: 1024 * 1024 * 1024, // 1 GB
      );
      expect(DeviceProfile.isConstrained, isTrue);
      expect(DeviceProfile.totalMemBytes, 1024 * 1024 * 1024);

      // Verify budget constraints for demux / image cache (1GB TV optimized)
      expect(int.parse(DeviceProfile.constrainedFwdBytes), 8 * 1024 * 1024);
      expect(int.parse(DeviceProfile.constrainedBackBytes), 2 * 1024 * 1024);
      expect(DeviceProfile.constrainedImageCacheCount, 30);
      expect(DeviceProfile.constrainedImageCacheBytes, 24 * 1024 * 1024);
      expect(DeviceProfile.constrainedProbeEarlyBatch, 2);
      expect(DeviceProfile.constrainedCoverMemWidth, 180);
      expect(DeviceProfile.constrainedHwdecExtraFrames, '1');
    });

    test('applyImageCacheLimits modifies PaintingBinding imageCache under constrained', () {
      WidgetsFlutterBinding.ensureInitialized();
      DeviceProfile.debugOverride(tier: DeviceProfileTier.constrained);
      DeviceProfile.applyImageCacheLimits();

      final cache = PaintingBinding.instance.imageCache;
      expect(cache.maximumSize, 30);
      expect(cache.maximumSizeBytes, 24 * 1024 * 1024);
    });

    test('trimImageCacheOnPlayerEnter clears live images and cache under constrained', () {
      WidgetsFlutterBinding.ensureInitialized();
      DeviceProfile.debugOverride(tier: DeviceProfileTier.constrained);
      DeviceProfile.applyImageCacheLimits();

      // Should run without exceptions
      DeviceProfile.trimImageCacheOnPlayerEnter();
      final cache = PaintingBinding.instance.imageCache;
      expect(cache.currentSize, 0);
    });
  });
}
