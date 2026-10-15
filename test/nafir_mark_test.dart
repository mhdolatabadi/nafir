import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/design/design.dart';
import 'package:nafir/core/widgets/nafir_mark.dart';

void main() {
  testWidgets('logo mark paints the r monogram at its requested size',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Center(child: NafirMark(size: 32)),
      ),
    );

    expect(tester.getSize(find.byType(NafirMark)), const Size(32, 32));
    expect(
      find.descendant(
        of: find.byType(NafirMark),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is NafirMarkPainter,
        ),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('ریتمو'), findsOneWidget);
  });

  test('logo tile matches the app icon background', () {
    expect(NafirColors.markTile, const Color(0xFF0B0D16));
  });
}
