import 'package:flutter_test/flutter_test.dart';
import 'package:sot/main.dart';

void main() {
  testWidgets('shows setup instructions without Supabase configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const SotApp());

    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });
}
