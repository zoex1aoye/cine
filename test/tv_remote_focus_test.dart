import 'package:cine/utils/cine_surface.dart';
import 'package:cine/utils/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => debugIsTvSurfaceOverride = true);
  tearDown(() => debugIsTvSurfaceOverride = null);

  test('详情页仅在内部全屏启用播控键', () {
    expect(tvTransportKeysEnabled(false), isFalse);
    expect(tvTransportKeysEnabled(true), isTrue);
    debugIsTvSurfaceOverride = false;
    expect(tvTransportKeysEnabled(true), isFalse);
  });

  test('全屏信号成对持有，播放页返回才不会多弹一层', () {
    TvFullscreenSignal.debugReset();
    expect(TvFullscreenSignal.active, isFalse);
    TvFullscreenSignal.retain();
    expect(TvFullscreenSignal.active, isTrue);
    TvFullscreenSignal.retain();
    TvFullscreenSignal.release();
    expect(TvFullscreenSignal.active, isTrue);
    TvFullscreenSignal.release();
    expect(TvFullscreenSignal.active, isFalse);
    TvFullscreenSignal.release();
    expect(TvFullscreenSignal.active, isFalse);
  });

  testWidgets('分类芯片可用方向键移动并用 OK 激活', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < 3; i++)
                SizedBox(
                  width: 80,
                  height: 40,
                  child: TvFocusable(
                    autofocus: i == 0,
                    onActivate: () => selected = i,
                    child: Text('分类$i'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(selected, 1);
  });

  testWidgets('隐藏页的焦点不会接到方向键', (tester) async {
    final hits = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 80,
                height: 40,
                child: TvFocusable(
                  autofocus: true,
                  onActivate: () => hits.add('visible'),
                  child: const Text('可见'),
                ),
              ),
              ExcludeFocus(
                excluding: true,
                child: SizedBox(
                  width: 80,
                  height: 40,
                  child: TvFocusable(
                    onActivate: () => hits.add('hidden'),
                    child: const Text('隐藏'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(hits, ['visible']);
  });
}
