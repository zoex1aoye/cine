import 'package:cine/player/hwdec_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness {
  _Harness({bool? probeResult = false}) : _probe = probeResult {
    dog = HwdecWatchdog(
      hasRenderedFrame: () async {
        probeCalls++;
        if (_throwOnProbe) throw StateError('probe failed');
        return _probe;
      },
      onStall: () => stalls++,
    );
  }

  late final HwdecWatchdog dog;
  bool? _probe;
  bool _throwOnProbe = false;
  int probeCalls = 0;
  int stalls = 0;

  void throwOnProbe() => _throwOnProbe = true;

  void startHealthyPlayback() {
    dog
      ..setEnabled(true)
      ..setHasVideoTrack(true)
      ..setBuffering(false)
      ..setPlaying(true);
  }
}

void main() {
  testWidgets('5 秒无帧输出 → 触发一次 onStall', (tester) async {
    final h = _Harness(probeResult: false)..startHealthyPlayback();
    await tester.pump(const Duration(seconds: 4));
    expect(h.stalls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(h.probeCalls, 1);
    expect(h.stalls, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(h.stalls, 1, reason: '触发后本源不应重复触发');
  });

  testWidgets('已有帧输出 → 不触发', (tester) async {
    final h = _Harness(probeResult: true)..startHealthyPlayback();
    await tester.pump(const Duration(seconds: 6));
    expect(h.probeCalls, 1);
    expect(h.stalls, 0);
  });

  testWidgets('弱网缓冲会清零计时，缓冲期间不判假死', (tester) async {
    final h = _Harness(probeResult: false)..startHealthyPlayback();
    await tester.pump(const Duration(seconds: 4));
    h.dog.setBuffering(true);
    await tester.pump(const Duration(seconds: 30));
    expect(h.stalls, 0);
    expect(h.probeCalls, 0);

    h.dog.setBuffering(false);
    await tester.pump(const Duration(seconds: 4));
    expect(h.stalls, 0, reason: '缓冲结束后应重新累计 5 秒');
    await tester.pump(const Duration(seconds: 2));
    expect(h.stalls, 1);
  });

  testWidgets('暂停起播不计时', (tester) async {
    final h = _Harness(probeResult: false)
      ..dog.setEnabled(true)
      ..dog.setHasVideoTrack(true)
      ..dog.setPlaying(false);
    await tester.pump(const Duration(seconds: 30));
    expect(h.probeCalls, 0);
    expect(h.stalls, 0);
  });

  testWidgets('纯音频（无视频轨）不计时', (tester) async {
    final h = _Harness(probeResult: false)
      ..dog.setEnabled(true)
      ..dog.setHasVideoTrack(false)
      ..dog.setPlaying(true);
    await tester.pump(const Duration(seconds: 30));
    expect(h.stalls, 0);
  });

  testWidgets('软解（未启用）不计时', (tester) async {
    final h = _Harness(probeResult: false)..startHealthyPlayback();
    h.dog.setEnabled(false);
    await tester.pump(const Duration(seconds: 30));
    expect(h.stalls, 0);
  });

  testWidgets('宽高事件先到（markFrameRendered）→ 不触发', (tester) async {
    final h = _Harness(probeResult: false)..startHealthyPlayback();
    await tester.pump(const Duration(seconds: 2));
    h.dog.markFrameRendered();
    await tester.pump(const Duration(seconds: 30));
    expect(h.probeCalls, 0);
    expect(h.stalls, 0);
  });

  testWidgets('探测不可用（null / 抛错）→ 宁可漏判不误切软解', (tester) async {
    final unknown = _Harness(probeResult: null)..startHealthyPlayback();
    await tester.pump(const Duration(seconds: 6));
    expect(unknown.stalls, 0);

    final broken = _Harness()
      ..throwOnProbe()
      ..startHealthyPlayback();
    await tester.pump(const Duration(seconds: 6));
    expect(broken.stalls, 0);
  });

  testWidgets('换源后重新监控', (tester) async {
    final h = _Harness(probeResult: true)..startHealthyPlayback();
    await tester.pump(const Duration(seconds: 6));
    expect(h.probeCalls, 1);

    h.dog.resetForNewSource();
    h.dog.setHasVideoTrack(true);
    await tester.pump(const Duration(seconds: 6));
    expect(h.probeCalls, 2);
  });

  testWidgets('dispose 后不再触发', (tester) async {
    final h = _Harness(probeResult: false)..startHealthyPlayback();
    h.dog.dispose();
    await tester.pump(const Duration(seconds: 30));
    expect(h.stalls, 0);
  });
}
