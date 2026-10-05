import 'package:cine/player/seek_hold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('短按只跳 10 秒，松开后再按仍是 10 秒', () {
    final hold = SeekHold();
    expect(hold.take(1, Duration.zero), 10);
    expect(hold.take(1, const Duration(milliseconds: 50)), isNull);
    hold.reset();
    expect(hold.take(1, const Duration(milliseconds: 80)), 10);
    expect(hold.take(-1, const Duration(milliseconds: 90)), -10);
  });

  test('按住超过 0.7 秒后跳 30 秒，超过 1.6 秒后跳 60 秒', () {
    final hold = SeekHold();
    expect(hold.take(-1, Duration.zero), -10);
    expect(hold.take(-1, const Duration(milliseconds: 250)), -10);
    expect(hold.take(-1, const Duration(milliseconds: 500)), -10);
    expect(hold.take(-1, const Duration(milliseconds: 800)), -30);
    expect(hold.take(-1, const Duration(milliseconds: 1100)), -30);
    expect(hold.take(-1, const Duration(milliseconds: 1400)), -30);
    expect(hold.take(-1, const Duration(milliseconds: 1700)), -60);
  });

  test('间隔超过 400 毫秒视为新的一次短按', () {
    final hold = SeekHold();
    expect(hold.take(1, Duration.zero), 10);
    expect(hold.take(1, const Duration(milliseconds: 200)), 10);
    expect(hold.take(1, const Duration(milliseconds: 500)), 10);
    expect(hold.take(1, const Duration(milliseconds: 800)), 30);
    expect(hold.take(1, const Duration(milliseconds: 1100)), 30);
    expect(hold.take(1, const Duration(milliseconds: 1400)), 30);
    expect(hold.take(1, const Duration(milliseconds: 1700)), 60);
    expect(hold.take(1, const Duration(milliseconds: 2200)), 10);
  });
}
