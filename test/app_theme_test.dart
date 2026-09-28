import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';

void main() {
  group('NafirTheme', () {
    final theme = NafirTheme.dark();

    test('keeps the established dark visual identity', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(
        theme.scaffoldBackgroundColor,
        theme.colorScheme.surfaceContainerLowest,
      );
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
    });

    test('uses accessible touch targets for primary controls', () {
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve({}),
        const Size(64, 48),
      );
      expect(
        theme.outlinedButtonTheme.style?.minimumSize?.resolve({}),
        const Size(64, 48),
      );
      expect(
        theme.textButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 48),
      );
      expect(
        theme.iconButtonTheme.style?.minimumSize?.resolve({}),
        const Size.square(48),
      );
    });

    test('provides consistent elevated surfaces and feedback', () {
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(
        theme.inputDecorationTheme.fillColor,
        const Color(0xB31B1E2D),
      );
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.searchBarTheme.constraints?.minHeight, 56);
    });

    test('separates major surfaces with restrained depth', () {
      expect(theme.cardTheme.color, const Color(0xB31A1D2A));
      expect(theme.cardTheme.elevation, 0);
      expect(theme.tabBarTheme.dividerColor, Colors.transparent);
      expect(theme.sliderTheme.trackHeight, 3);
      expect(theme.bottomSheetTheme.showDragHandle, isTrue);
    });
  });
}
