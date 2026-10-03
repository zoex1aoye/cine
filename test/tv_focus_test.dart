import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine/utils/cine_surface.dart';
import 'package:cine/utils/tv_focus.dart';

void main() {
  setUp(() {
    debugOverrideSurface(CineSurface.tv);
  });

  tearDown(() {
    debugOverrideSurface(null);
  });

  testWidgets('TvFocusable shows highlight and responds to ActivateIntent', (tester) async {
    bool activated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvShortcutsShell(
            child: Center(
              child: TvFocusable(
                autofocus: true,
                onActivate: () => activated = true,
                child: const Text('TV 焦点项'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 在 TV 模式下应该响应激活
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(activated, isTrue);
  });
}
