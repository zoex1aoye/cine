import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine/utils/device_profile.dart';

const _gib = 1 << 30;

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

  group('档位推导 tierFor', () {
    test('<=1.2GiB 为 ultra（1GB 级电视/投影）', () {
      expect(
        DeviceBudget.tierFor(totalMemBytes: 1 * _gib),
        DeviceProfileTier.ultra,
      );
      expect(
        DeviceBudget.tierFor(totalMemBytes: 900 << 20),
        DeviceProfileTier.ultra,
      );
      expect(
        DeviceBudget.tierFor(totalMemBytes: DeviceBudget.ultraMaxTotalMem),
        DeviceProfileTier.ultra,
      );
    });

    test('1.2GiB ~ 2GiB 为 constrained（标称 2GB 上报 ~1.9GiB）', () {
      expect(
        DeviceBudget.tierFor(totalMemBytes: (1.9 * _gib).round()),
        DeviceProfileTier.constrained,
      );
      expect(
        DeviceBudget.tierFor(totalMemBytes: (1.5 * _gib).round()),
        DeviceProfileTier.constrained,
      );
    });

    test('>=2GiB 为 normal', () {
      expect(
        DeviceBudget.tierFor(totalMemBytes: 2 * _gib),
        DeviceProfileTier.normal,
      );
      expect(
        DeviceBudget.tierFor(totalMemBytes: 4 * _gib),
        DeviceProfileTier.normal,
      );
    });

    test('系统 low-ram 标记即使内存读数偏大也归 ultra；读不到内存则只看标记', () {
      expect(
        DeviceBudget.tierFor(totalMemBytes: 3 * _gib, lowRam: true),
        DeviceProfileTier.ultra,
      );
      expect(DeviceBudget.tierFor(lowRam: true), DeviceProfileTier.ultra);
      expect(DeviceBudget.tierFor(), DeviceProfileTier.normal);
      expect(DeviceBudget.tierFor(totalMemBytes: 0), DeviceProfileTier.normal);
    });
  });

  group('预算单调：越受限越小', () {
    int mb(String bytes) => int.parse(bytes);

    test('demux 缓冲 normal > constrained > ultra', () {
      const n = DeviceBudget.normal;
      const c = DeviceBudget.constrained;
      const u = DeviceBudget.ultra;
      expect(mb(n.demuxFwdBytes), greaterThan(mb(c.demuxFwdBytes)));
      expect(mb(c.demuxFwdBytes), greaterThan(mb(u.demuxFwdBytes)));
      expect(mb(n.demuxBackBytes), greaterThan(mb(c.demuxBackBytes)));
      expect(mb(c.demuxBackBytes), greaterThan(mb(u.demuxBackBytes)));
    });

    test('ultra 后向缓冲不低于 4MB（保证 -10s 不必每次回源）', () {
      expect(
        mb(DeviceBudget.ultra.demuxBackBytes),
        greaterThanOrEqualTo(4 << 20),
      );
    });

    test('封面解码宽度 normal > constrained > ultra', () {
      expect(
        DeviceBudget.normal.coverDecodeMaxWidth,
        greaterThan(DeviceBudget.constrained.coverDecodeMaxWidth),
      );
      expect(
        DeviceBudget.constrained.coverDecodeMaxWidth,
        greaterThan(DeviceBudget.ultra.coverDecodeMaxWidth),
      );
    });

    test('图片缓存张数不再是瓶颈：按字节预算，张数 >= 100', () {
      for (final b in [DeviceBudget.constrained, DeviceBudget.ultra]) {
        expect(b.imageCacheCount, greaterThanOrEqualTo(100));
      }
      expect(DeviceBudget.ultra.imageCacheBytes, 24 << 20);
      expect(DeviceBudget.constrained.imageCacheBytes, 48 << 20);
    });
  });

  group('DeviceProfile 运行态', () {
    test('默认 normal，isConstrained/isUltra 为 false', () {
      expect(DeviceProfile.tier, DeviceProfileTier.normal);
      expect(DeviceProfile.isConstrained, isFalse);
      expect(DeviceProfile.isUltra, isFalse);
    });

    test('constrained 与 ultra 都视为 isConstrained；只有 ultra 为 isUltra', () {
      DeviceProfile.debugOverride(tier: DeviceProfileTier.constrained);
      expect(DeviceProfile.isConstrained, isTrue);
      expect(DeviceProfile.isUltra, isFalse);
      DeviceProfile.debugOverride(tier: DeviceProfileTier.ultra);
      expect(DeviceProfile.isConstrained, isTrue);
      expect(DeviceProfile.isUltra, isTrue);
    });

    test('applyImageCacheLimits 按档位写入 ImageCache；normal 不动', () {
      WidgetsFlutterBinding.ensureInitialized();
      final cache = PaintingBinding.instance.imageCache;
      final defaultCount = cache.maximumSize;
      final defaultBytes = cache.maximumSizeBytes;

      DeviceProfile.applyImageCacheLimits();
      expect(cache.maximumSize, defaultCount);
      expect(cache.maximumSizeBytes, defaultBytes);

      DeviceProfile.debugOverride(tier: DeviceProfileTier.ultra);
      DeviceProfile.applyImageCacheLimits();
      expect(cache.maximumSize, DeviceBudget.ultra.imageCacheCount);
      expect(cache.maximumSizeBytes, 24 << 20);

      cache.maximumSize = defaultCount;
      cache.maximumSizeBytes = defaultBytes;
    });
  });

  trimTests();
}

class _TrimHarness {
  _TrimHarness(this.cache);
  final ImageCache cache;
  final _keep = <ImageStreamListener>[];

  ImageStreamCompleter put(Object key, ImageInfo info, {required bool live}) {
    final completer =
        cache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(Future.value(info)),
        )!;
    if (live) {
      final l = ImageStreamListener((_, __) {});
      _keep.add(l);
      completer.addListener(l);
    }
    return completer;
  }
}

void trimTests() {
  group('trimImageCacheOnPlayerEnter', () {
    testWidgets('受限档：驱逐空闲项，仍被引用的 live 图片不受影响', (tester) async {
      final image =
          (await tester.runAsync(() => createTestImage(width: 4, height: 4)))!;
      final cache = PaintingBinding.instance.imageCache..clear();
      final h = _TrimHarness(cache);
      h.put('idle', ImageInfo(image: image.clone()), live: false);
      h.put('onscreen', ImageInfo(image: image.clone()), live: true);
      await tester.pump();
      expect(cache.containsKey('idle'), isTrue);

      DeviceProfile.debugOverride(tier: DeviceProfileTier.ultra);
      DeviceProfile.trimImageCacheOnPlayerEnter();

      expect(cache.containsKey('idle'), isFalse, reason: '空闲封面应被释放');
      expect(
        cache.statusForKey('onscreen').live,
        isTrue,
        reason: '仍在下层页面显示的封面不应失去追踪',
      );
      cache.clear();
    });

    testWidgets('常规档：完全不动缓存', (tester) async {
      final image =
          (await tester.runAsync(() => createTestImage(width: 4, height: 4)))!;
      final cache = PaintingBinding.instance.imageCache..clear();
      final h = _TrimHarness(cache);
      h.put('idle', ImageInfo(image: image.clone()), live: false);
      await tester.pump();

      DeviceProfile.trimImageCacheOnPlayerEnter();

      expect(cache.containsKey('idle'), isTrue);
      cache.clear();
    });

    testWidgets('onTrimMemory (level >= 15) 触发 clear() 驱逐空闲项', (tester) async {
      final image =
          (await tester.runAsync(() => createTestImage(width: 4, height: 4)))!;
      final cache = PaintingBinding.instance.imageCache..clear();
      final h = _TrimHarness(cache);
      h.put('idle', ImageInfo(image: image.clone()), live: false);
      h.put('onscreen', ImageInfo(image: image.clone()), live: true);
      await tester.pump();
      expect(cache.containsKey('idle'), isTrue);

      DeviceProfile.handleTrimMemory(20);

      expect(
        cache.containsKey('idle'),
        isFalse,
        reason: '收到 onTrimMemory >= 15 应释放空闲项',
      );
      expect(
        cache.statusForKey('onscreen').live,
        isTrue,
        reason: '正在渲染的 live 项保留',
      );
      cache.clear();
    });
  });
}
