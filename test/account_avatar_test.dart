import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/core/design/design.dart';

Future<void> _pump(WidgetTester tester, {required bool verified}) =>
    tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: AccountAvatar(verified: verified)),
        ),
      ),
    ));

void main() {
  testWidgets('a verified account carries a blue check', (tester) async {
    await _pump(tester, verified: true);

    final badge = find.byKey(const ValueKey('verified-badge'));
    expect(badge, findsOneWidget);
    final check = tester
        .widget<Icon>(find.descendant(of: badge, matching: find.byType(Icon)));
    expect(check.color, RhythmoColors.verified);
    expect(find.bySemanticsLabel('حساب تأییدشده'), findsOneWidget);
  });

  testWidgets('an unverified account shows only its icon', (tester) async {
    await _pump(tester, verified: false);

    expect(find.byKey(const ValueKey('verified-badge')), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });
}
