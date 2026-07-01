import 'package:flutter_test/flutter_test.dart';
import 'package:cine/widgets/episode_grid_layout.dart';

void main() {
  group('EpisodeGridLayout', () {
    test('phone portrait uses ~3 columns and moderate aspect', () {
      final m = EpisodeGridLayout.metrics(
        panelWidth: 342,
        screenWidth: 390,
        itemCount: 24,
        hasLongLabel: false,
      );
      expect(m.crossAxisCount, 3);
      expect(m.childAspectRatio, greaterThan(1.8));
      expect(m.childAspectRatio, lessThan(2.4));
    });

    test('phone landscape sidebar stays compact for movie versions', () {
      final m = EpisodeGridLayout.metrics(
        panelWidth: 270,
        screenWidth: 844,
        itemCount: 3,
        hasLongLabel: true,
      );
      expect(m.crossAxisCount, 2);
      expect(m.childAspectRatio, greaterThan(2.0));
    });

    test('tablet panel scales columns with width', () {
      final m = EpisodeGridLayout.metrics(
        panelWidth: 520,
        screenWidth: 1024,
        itemCount: 12,
        hasLongLabel: false,
      );
      expect(m.crossAxisCount, greaterThanOrEqualTo(3));
      expect(m.crossAxisCount, lessThanOrEqualTo(6));
    });

    test('desktop wide panel fits more numbered episodes', () {
      final m = EpisodeGridLayout.metrics(
        panelWidth: 480,
        screenWidth: 1440,
        itemCount: 40,
        hasLongLabel: false,
      );
      expect(m.crossAxisCount, greaterThanOrEqualTo(3));
      expect(m.spacing, 8);
    });

    test('4K TV panel uses wider spacing and taller tiles', () {
      final phone = EpisodeGridLayout.metrics(
        panelWidth: 342,
        screenWidth: 390,
        itemCount: 24,
        hasLongLabel: false,
      );
      final tv = EpisodeGridLayout.metrics(
        panelWidth: 1150,
        screenWidth: 3840,
        itemCount: 24,
        hasLongLabel: false,
      );
      expect(tv.spacing, greaterThan(phone.spacing));
      expect(
        EpisodeGridLayout.targetCellHeight(3840, hasLongLabel: false),
        greaterThan(
          EpisodeGridLayout.targetCellHeight(390, hasLongLabel: false),
        ),
      );
      expect(tv.crossAxisCount, greaterThan(phone.crossAxisCount));
    });
  });
}
