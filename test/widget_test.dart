import 'package:flutter_test/flutter_test.dart';
import 'package:sot/main.dart';

void main() {
  testWidgets('shows the empty library state', (tester) async {
    await tester.pumpWidget(const SotApp());

    expect(find.text('SOT موسیقی'), findsOneWidget);
    expect(find.text('کتابخانهٔ شما خالی است'), findsOneWidget);
  });
}
