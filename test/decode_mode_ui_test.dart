import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Decode mode badge toggles between hardware and software decode', (tester) async {
    final isHwNotifier = ValueNotifier<bool>(true);
    bool toggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: isHwNotifier,
            builder: (context, isHw, _) {
              return TextButton.icon(
                icon: Icon(isHw ? Icons.memory : Icons.developer_board),
                label: Text(isHw ? '硬解' : '软解'),
                onPressed: () {
                  toggled = true;
                  isHwNotifier.value = !isHwNotifier.value;
                },
              );
            },
          ),
        ),
      ),
    );

    // Initial state: 硬解
    expect(find.text('硬解'), findsOneWidget);
    expect(find.byIcon(Icons.memory), findsOneWidget);

    // Tap to toggle
    await tester.tap(find.text('硬解'));
    await tester.pump();

    expect(toggled, isTrue);
    expect(isHwNotifier.value, isFalse);
    expect(find.text('软解'), findsOneWidget);
    expect(find.byIcon(Icons.developer_board), findsOneWidget);
  });
}
