import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/main.dart';

void main() {
  testWidgets('shows setup instructions without API configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const NafirApp());

    expect(find.textContaining('API_BASE_URL'), findsOneWidget);
  });

  testWidgets('shows library when the API is healthy', (tester) async {
    await tester.pumpWidget(NafirApp(healthCheck: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('کتابخانهٔ شما خالی است'), findsOneWidget);
  });

  testWidgets('shows retry when the API is unavailable', (tester) async {
    await tester.pumpWidget(
      NafirApp(healthCheck: () async => throw Exception('offline')),
    );
    await tester.pumpAndSettle();

    expect(find.text('اتصال به سرور برقرار نشد'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });
}
