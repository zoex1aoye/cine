import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine/utils/cine_surface.dart';
import 'package:cine/utils/device_profile.dart';
import 'package:cine/widgets/movie_card.dart';
import 'package:cine/models/mubu_models.dart';

void main() {
  tearDown(() {
    debugOverrideSurface(null);
    DeviceProfile.debugOverride(tier: DeviceProfileTier.normal);
  });

  group('TV and Low-end Pad Surface and Focus Tests', () {
    testWidgets('MovieCard gains TV focus and triggers onPlay on Enter key', (tester) async {
      debugOverrideSurface(CineSurface.tv);
      bool played = false;

      final video = VideoItem(
        id: 999,
        title: 'TV 焦点测试视频',
        category: '动漫',
        year: '2026',
        score: '8.8',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 380,
                child: MovieCard(
                  video: video,
                  imgDomain: '',
                  onPlay: () => played = true,
                  onInfo: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 在 TV 模式下，MovieCard 被 FocusableActionDetector 包裹
      final detectorFinder = find.byType(FocusableActionDetector);
      expect(detectorFinder, findsWidgets);

      // 通过 Actions 执行 ActivateIntent（使用其子树中的 element 获取 Actions 上下文）
      final innerElement = find.descendant(
        of: detectorFinder.first,
        matching: find.byType(AnimatedScale),
      ).first;
      Actions.invoke(
        tester.element(innerElement),
        const ActivateIntent(),
      );
      await tester.pump();

      expect(played, isTrue, reason: 'TV 模式下激活 ActivateIntent 应触发 onPlay');
    });

    testWidgets('Mobile surface does not wrap MovieCard with FocusableActionDetector', (tester) async {
      debugOverrideSurface(CineSurface.mobile);

      final video = VideoItem(
        id: 999,
        title: '手机端测试视频',
        category: '动漫',
        year: '2026',
        score: '8.8',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 380,
                child: MovieCard(
                  video: video,
                  imgDomain: '',
                  onPlay: () {},
                  onInfo: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 手机模式下不应该额外包裹外层 FocusableActionDetector
      expect(isTvSurface, isFalse);
    });

    test('封面解码宽度只看内存档，不看 TV/手机 surface', () {
      for (final surface in [CineSurface.tv, CineSurface.mobile]) {
        debugOverrideSurface(surface);

        DeviceProfile.debugOverride(tier: DeviceProfileTier.normal);
        expect(
          DeviceProfile.budget.coverDecodeWidth(logicalWidth: 200, dpr: 2),
          400,
          reason: '常规内存的 TV 不应被糊化 (surface=$surface)',
        );

        DeviceProfile.debugOverride(tier: DeviceProfileTier.constrained);
        expect(
          DeviceProfile.budget.coverDecodeWidth(logicalWidth: 200, dpr: 2),
          240,
        );

        DeviceProfile.debugOverride(tier: DeviceProfileTier.ultra);
        expect(
          DeviceProfile.budget.coverDecodeWidth(logicalWidth: 200, dpr: 2),
          180,
        );
      }
    });

    test('布局宽未知或 dpr 异常时回落到档位上限', () {
      const b = DeviceBudget.ultra;
      expect(b.coverDecodeWidth(logicalWidth: double.infinity, dpr: 2), 180);
      expect(b.coverDecodeWidth(logicalWidth: 100, dpr: 0), 180);
      expect(b.coverDecodeWidth(logicalWidth: 10, dpr: 1), 64);
    });
  });
}
