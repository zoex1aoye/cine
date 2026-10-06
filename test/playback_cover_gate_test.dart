import 'package:cached_network_image/cached_network_image.dart';
import 'package:cine/utils/device_profile.dart';
import 'package:cine/utils/playback_cover_gate.dart';
import 'package:cine/widgets/failover_cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PlaybackCoverGate.debugReset();
    DeviceProfile.debugOverride(
      tier: DeviceProfileTier.normal,
      resetInitialized: true,
    );
  });

  tearDown(() {
    PlaybackCoverGate.debugReset();
    DeviceProfile.debugOverride(
      tier: DeviceProfileTier.normal,
      resetInitialized: true,
    );
  });

  group('PlaybackCoverGate', () {
    test('嵌套 acquire 按深度释放，归零后不再挡住封面', () {
      expect(PlaybackCoverGate.isHeld, isFalse);
      PlaybackCoverGate.acquire();
      PlaybackCoverGate.acquire();
      expect(PlaybackCoverGate.isHeld, isTrue);
      PlaybackCoverGate.release();
      expect(PlaybackCoverGate.isHeld, isTrue);
      PlaybackCoverGate.release();
      expect(PlaybackCoverGate.isHeld, isFalse);
      PlaybackCoverGate.release();
      expect(PlaybackCoverGate.isHeld, isFalse);
    });
  });

  group('FailoverCoverImage 被播放页盖住', () {
    Future<void> pumpCover(
      WidgetTester tester, {
      bool holdDuringPlayback = false,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FailoverCoverImage(
              coverPath: '/poster.jpg',
              imgDomain: 'img.example',
              candidates: const ['img.example'],
              holdDuringPlayback: holdDuringPlayback,
            ),
          ),
        ),
      );
    }

    testWidgets('受限档盖住时卸掉 ImageStream，松开后恢复', (tester) async {
      DeviceProfile.debugOverride(tier: DeviceProfileTier.ultra);
      PlaybackCoverGate.acquire();

      await pumpCover(tester);

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == const Color(0xFF1A1A1E),
        ),
        findsOneWidget,
      );

      PlaybackCoverGate.release();
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('播放页自己的背景在盖住期间仍解码', (tester) async {
      DeviceProfile.debugOverride(tier: DeviceProfileTier.constrained);
      PlaybackCoverGate.acquire();

      await pumpCover(tester, holdDuringPlayback: true);

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('常规档即使闸门拉起也不卸封面', (tester) async {
      PlaybackCoverGate.acquire();

      await pumpCover(tester);

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
