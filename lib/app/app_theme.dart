import 'package:flutter/material.dart';

abstract final class NafirTheme {
  static const _seed = Color(0xFF1A73E8);
  static const _controlRadius = 14.0;
  static const _surfaceRadius = 18.0;

  static ThemeData dark() {
    final colors = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: colors,
      fontFamily: 'Vazirmatn',
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
    );
    final surfaceShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_surfaceRadius),
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
      borderSide: BorderSide(color: colors.outlineVariant),
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: surfaceShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: base.textTheme.bodyLarge?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.6,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: surfaceShape,
        position: PopupMenuPosition.under,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        actionTextColor: colors.inversePrimary,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
        iconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        selectedColor: colors.onSecondaryContainer,
        selectedTileColor: colors.secondaryContainer,
        shape: controlShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
        errorStyle: TextStyle(color: colors.error),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_surfaceRadius),
            side: BorderSide(color: colors.outlineVariant),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        constraints: const BoxConstraints(minHeight: 56),
        hintStyle: WidgetStatePropertyAll(
          base.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          base.textTheme.bodyLarge?.copyWith(color: colors.onSurface),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(
            base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(controlShape),
          side: WidgetStatePropertyAll(
            BorderSide(color: colors.outline),
          ),
          textStyle: WidgetStatePropertyAll(
            base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.square(48)),
          iconSize: const WidgetStatePropertyAll(22),
          shape: const WidgetStatePropertyAll(CircleBorder()),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: colors.onInverseSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }
}
