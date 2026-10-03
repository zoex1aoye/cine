import 'package:cine/player/tv_player_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe {
  bool controlsVisible = false;
  int shown = 0;
  final seeks = <Duration>[];
  final volumes = <double>[];
  int playPauses = 0;
  int exitFullscreenCalls = 0;
  bool inFullscreen = true;
  int decodeToggles = 0;

  final entry = FocusNode(debugLabel: 'entry');
  final decode = FocusNode(debugLabel: 'decode');

  late final actions = TvPlayerKeyActions(
    controlsVisible: () => controlsVisible,
    showControls: () {
      shown++;
      controlsVisible = true;
    },
    seekBy: seeks.add,
    nudgeVolume: volumes.add,
    playOrPause: () => playPauses++,
    exitFullscreen: () {
      exitFullscreenCalls++;
      final was = inFullscreen;
      inFullscreen = false;
      return was;
    },
    focusChrome: () {
      entry.requestFocus();
      return true;
    },
  );
}

Future<void> _pump(WidgetTester tester, _Probe p) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => handleTvPlayerKey(node, event, p.actions),
        child: Scaffold(
          body: Row(
            children: [
              TextButton(
                focusNode: p.entry,
                onPressed: () {},
                child: const Text('fullscreen'),
              ),
              TextButton(
                focusNode: p.decode,
                onPressed: () => p.decodeToggles++,
                child: const Text('decode'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('焦点在根：←/→ 快进退 10s，↓ 音量-5，OK 播放暂停', (tester) async {
    final p = _Probe();
    await _pump(tester, p);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);

    expect(p.seeks, [const Duration(seconds: -10), const Duration(seconds: 10)]);
    expect(p.volumes, [-5]);
    expect(p.playPauses, 1);
  });

  testWidgets('控件栏隐藏时 ↑ 加音量；可见时 ↑ 进入控件栏', (tester) async {
    final p = _Probe();
    await _pump(tester, p);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(p.volumes, [5]);
    expect(p.entry.hasFocus, isFalse);

    expect(p.controlsVisible, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(p.entry.hasPrimaryFocus, isTrue);
    expect(p.volumes, [5], reason: '进入控件栏不应再调音量');
  });

  testWidgets('回归：焦点在控件栏时 →/OK 不被祖先吞掉，能到达并激活解码按钮', (tester) async {
    final p = _Probe();
    await _pump(tester, p);
    p.entry.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(p.decode.hasPrimaryFocus, isTrue);
    expect(p.seeks, isEmpty, reason: '控件栏内方向键不能触发快进');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(p.decodeToggles, 1);
    expect(p.playPauses, 0, reason: 'OK 应激活按钮而不是播放暂停');
  });

  testWidgets('返回键：控件栏内先回根，再次返回才退出内部全屏', (tester) async {
    final p = _Probe();
    await _pump(tester, p);
    p.decode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(p.decode.hasFocus, isFalse);
    expect(p.exitFullscreenCalls, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(p.exitFullscreenCalls, 1);
  });

  testWidgets('不在内部全屏时返回键放行（交给页面 pop）', (tester) async {
    final p = _Probe()..inFullscreen = false;
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                popped = true,
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: (n, e) => handleTvPlayerKey(n, e, p.actions),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(p.exitFullscreenCalls, 1);
    expect(popped, isTrue);
  });
}
