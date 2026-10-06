import 'package:cine/player/center_play_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortest side 360 keeps the previous 48/16 button', () {
    final m = CenterPlayButtonMetrics.forShortestSide(360);
    expect(m.icon, 48);
    expect(m.padding, 16);
  });

  test('small player shrinks the center button', () {
    final m = CenterPlayButtonMetrics.forShortestSide(180);
    expect(m.icon, 24);
    expect(m.padding, 8);
  });

  test('large player grows the button but stays capped', () {
    final m = CenterPlayButtonMetrics.forShortestSide(1080);
    expect(m.scale, CenterPlayButtonMetrics.maxScale);
    expect(m.icon, 48 * CenterPlayButtonMetrics.maxScale);
  });

  test('uses the player shortest side, not the longer one', () {
    final wide = CenterPlayButtonMetrics.forPlayer(1200, 180);
    expect(wide.icon, 24);
  });

  test('unbounded player size falls back to the reference button', () {
    final m = CenterPlayButtonMetrics.forPlayer(double.infinity, 400);
    expect(m.icon, 48);
    expect(m.padding, 16);
  });
}
