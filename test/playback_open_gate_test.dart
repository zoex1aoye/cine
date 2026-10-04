import 'package:cine/player/playback_open_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('后发起的换源让尚未开始的旧 open 跳过', () async {
    final gate = PlaybackOpenGate();
    final started = <int>[];
    final first = gate.run(gate.generation, () async {
      started.add(1);
    });
    final generation = gate.bump();
    final second = gate.run(generation, () async {
      started.add(2);
    });
    await Future.wait([first, second]);
    expect(started, [2]);
  });

  test('已经开始的 open 会跑完，下一次在它之后执行', () async {
    final gate = PlaybackOpenGate();
    final order = <int>[];
    final firstGen = gate.generation;
    final first = gate.run(firstGen, () async {
      order.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      order.add(2);
    });
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final generation = gate.bump();
    final second = gate.run(generation, () async {
      order.add(3);
    });
    await Future.wait([first, second]);
    expect(order, [1, 2, 3]);
  });
}
