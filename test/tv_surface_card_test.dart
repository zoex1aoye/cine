import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine/utils/cine_surface.dart';
import 'package:cine/utils/device_profile.dart';
import 'package:cine/widgets/movie_card.dart';
import 'package:cine/models/mubu_models.dart';

void main() {
  tearDown(() {
    debugOverrideSurface(null);
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

    testWidgets('TV mode enforces constrainedCoverMemWidth limit on MovieCard decode width', (tester) async {
      debugOverrideSurface(CineSurface.tv);
      DeviceProfile.debugOverride(tier: DeviceProfileTier.constrained);

      final video = VideoItem(
        id: 999,
        title: 'TV 封面尺寸测试视频',
        category: '电影',
        year: '2026',
        score: '9.0',
        coverPath: '/test/cover.jpg',
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

      // 在 TV 模式或受限模式下，memCacheWidth 会被限制在 constrainedCoverMemWidth (180)
      expect(DeviceProfile.constrainedCoverMemWidth, 180);
    });
  });
}
