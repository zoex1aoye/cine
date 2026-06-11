import 'package:flutter_test/flutter_test.dart';
import 'package:cine/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const MubuApp());
    expect(find.byType(MubuApp), findsOneWidget);
  });
}
