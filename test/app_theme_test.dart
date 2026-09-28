import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';

void main() {
  group('NafirTheme', () {
    final theme = NafirTheme.dark();

    test('keeps the established dark visual identity', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
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
        theme.colorScheme.surfaceContainerHigh,
      );
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.searchBarTheme.constraints?.minHeight, 56);
    });
  });
}
