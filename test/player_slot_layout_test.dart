import 'package:flutter_test/flutter_test.dart';
import 'package:cine/widgets/player_slot_layout.dart';

void main() {
  group('PlayerSlotLayout', () {
    test('movie slot height caps at 42% screen', () {
      final h = PlayerSlotLayout.slotHeight(
        width: 400,
        isShortDrama: false,
        screenHeight: 800,
      );
      expect(h, 225.0);
    });

    test('short drama slot uses 9:16 natural height with cap', () {
      final h = PlayerSlotLayout.slotHeight(
        width: 360,
        isShortDrama: true,
        screenHeight: 800,
      );
      expect(h, 520.0);
    });

    test('innerVideoSize letterboxes ultrawide in 16:9 slot', () {
      final size = PlayerSlotLayout.innerVideoSize(360, 202.5, 2.39);
      expect(size.width, closeTo(360, 0.01));
      expect(size.height, closeTo(150.6, 0.5));
    });

    test('shouldReplaceInnerRatio respects 5% drift', () {
      expect(
        PlayerSlotLayout.shouldReplaceInnerRatio(
          16 / 9,
          2.0,
          isShortDrama: false,
        ),
        isTrue,
      );
      expect(
        PlayerSlotLayout.shouldReplaceInnerRatio(
          1.78,
          1.80,
          isShortDrama: false,
        ),
        isFalse,
      );
    });
  });
}
