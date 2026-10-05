import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/settings/presentation/storage_usage_card.dart';

void main() {
  Future<void> pump(WidgetTester tester, int used, int limit) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StorageUsageCard(usedBytes: used, limitBytes: limit),
        ),
      ));

  const gib = 1024 * 1024 * 1024;

  testWidgets('shows use against the limit', (tester) async {
    await pump(tester, gib ~/ 4, gib);
    expect(find.text('۲۵۶.۰ مگابایت از ۱.۰ گیگابایت'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('پر است'), findsNothing);
  });

  testWidgets('warns when nearly full and when full', (tester) async {
    await pump(tester, (gib * 0.95).round(), gib);
    expect(find.text('فضای حسابت تقریباً پر است.'), findsOneWidget);

    await pump(tester, gib, gib);
    expect(find.textContaining('فضای حسابت پر است.'), findsOneWidget);
  });

  testWidgets('without a reported limit it shows only what is used',
      (tester) async {
    await pump(tester, 3 * 1024 * 1024, 0);
    expect(find.text('۳.۰ مگابایت مصرف‌شده'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
