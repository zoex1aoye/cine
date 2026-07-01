import 'package:flutter_test/flutter_test.dart';
import 'package:cine/widgets/player_overlay_metrics.dart';

void main() {
  group('PlayerOverlayMetrics.loadingHud', () {
    test('phone landscape short slot stays well below slot height', () {
      // ~844×390 phone, left player column ~540×164
      final m = PlayerOverlayMetrics.loadingHud(
        slotWidth: 540,
        slotHeight: 164,
        screenWidth: 844,
      );
      expect(m.outerDiameter, lessThan(164));
      expect(m.outerDiameter, lessThanOrEqualTo(96));
      expect(m.outerDiameter, greaterThan(56));
    });

    test('phone portrait scales to moderate HUD', () {
      final m = PlayerOverlayMetrics.loadingHud(
        slotWidth: 366,
        slotHeight: 206,
        screenWidth: 390,
      );
      expect(m.outerDiameter, lessThanOrEqualTo(108));
      expect(m.outerDiameter, greaterThan(72));
    });

    test('tablet and laptop grow progressively', () {
      final tablet = PlayerOverlayMetrics.loadingHud(
        slotWidth: 620,
        slotHeight: 348,
        screenWidth: 1024,
      );
      final laptop = PlayerOverlayMetrics.loadingHud(
        slotWidth: 820,
        slotHeight: 460,
        screenWidth: 1440,
      );
      expect(laptop.outerDiameter, greaterThan(tablet.outerDiameter));
    });

    test('4K and 8K TV cap at readable upper bounds', () {
      final k4 = PlayerOverlayMetrics.loadingHud(
        slotWidth: 1400,
        slotHeight: 630,
        screenWidth: 3840,
      );
      final k8 = PlayerOverlayMetrics.loadingHud(
        slotWidth: 2800,
        slotHeight: 1260,
        screenWidth: 7680,
      );
      expect(k4.outerDiameter, lessThanOrEqualTo(220));
      expect(k8.outerDiameter, lessThanOrEqualTo(248));
      expect(k8.outerDiameter, greaterThanOrEqualTo(k4.outerDiameter));
    });
  });

  group('PlayerOverlayMetrics.playButton', () {
    test('phone landscape play button is compact', () {
      final m = PlayerOverlayMetrics.playButton(
        slotWidth: 540,
        slotHeight: 164,
        screenWidth: 844,
      );
      expect(m.coreSize, lessThanOrEqualTo(64));
      expect(m.coreSize + m.pulseRange, lessThan(164));
    });
  });
}
