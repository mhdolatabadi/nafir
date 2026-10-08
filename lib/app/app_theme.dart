import 'package:flutter/material.dart';
import 'package:nafir/core/design/tokens.dart';

abstract final class NafirTheme {
  static const _seed = NafirColors.primary;
  static const _controlRadius = NafirRadii.md;
  static const _surfaceRadius = NafirRadii.lg;

  static ThemeData dark() {
    final colors = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    ).copyWith(
      primary: NafirColors.primary,
      onPrimary: NafirColors.onPrimary,
      primaryContainer: NafirColors.primaryContainer,
      onPrimaryContainer: NafirColors.onPrimaryContainer,
      secondary: NafirColors.secondary,
      onSecondary: NafirColors.onSecondary,
      secondaryContainer: NafirColors.secondaryContainer,
      onSecondaryContainer: NafirColors.onSecondaryContainer,
      surface: NafirColors.background,
      surfaceContainerLowest: NafirColors.background,
      surfaceContainerLow: NafirColors.containerLow,
      surfaceContainer: NafirColors.container,
      surfaceContainerHigh: NafirColors.containerHigh,
      surfaceContainerHighest: NafirColors.surfaceRaised,
      onSurface: NafirColors.onSurface,
      onSurfaceVariant: NafirColors.onSurfaceVariant,
      outline: NafirColors.outline,
      outlineVariant: NafirColors.outlineVariant,
    );
    final material = ThemeData(
      brightness: Brightness.dark,
      colorScheme: colors,
      fontFamily: NafirType.family,
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final base = material.copyWith(
      textTheme: NafirType.apply(material.textTheme),
      extensions: const [NafirTokens.dark],
      focusColor: NafirColors.primary.withValues(alpha: 0.24),
    );

    // Keyboard focus draws a 2 px ring on every button, on top of the
    // state layer, so it shows on any surface.
    WidgetStateProperty<BorderSide?> ring(BorderSide? rest) =>
        WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.focused)
                ? BorderSide(color: NafirTokens.dark.focusRing, width: 2)
                : rest);

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
      scaffoldBackgroundColor: NafirColors.background,
      canvasColor: NafirColors.background,
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: NafirColors.background.withValues(alpha: 0.58),
        foregroundColor: colors.onSurface,
        surfaceTintColor: NafirColors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(
          bottom: BorderSide(color: NafirColors.divider),
        ),
      ),
      cardTheme: CardThemeData(
        color: NafirColors.card,
        surfaceTintColor: NafirColors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: surfaceShape.copyWith(
          side: BorderSide(
            color: NafirColors.softBorder,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NafirColors.overlay,
        surfaceTintColor: NafirColors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: NafirRadii.panel,
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
        color: NafirColors.overlay,
        surfaceTintColor: NafirColors.transparent,
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
      tabBarTheme: TabBarThemeData(
        dividerColor: NafirColors.transparent,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(NafirRadii.pill),
          color: colors.primary.withValues(alpha: 0.18),
          border: Border.all(color: colors.primary.withValues(alpha: 0.42)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: colors.onSurface,
        unselectedLabelColor: colors.onSurfaceVariant,
        labelStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: base.textTheme.labelLarge,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.surfaceContainerHigh.withValues(alpha: 0.7),
        selectedColor: colors.secondary.withValues(alpha: 0.2),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NafirRadii.sm),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: NafirSpace.sm, vertical: NafirSpace.xs + 2),
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
        fillColor: NafirColors.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        backgroundColor: const WidgetStatePropertyAll(NafirColors.field),
        surfaceTintColor: const WidgetStatePropertyAll(NafirColors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(NafirColors.transparent),
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
          side: ring(null),
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
          side: ring(BorderSide(color: colors.outline)),
          textStyle: WidgetStatePropertyAll(
            base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          side: ring(null),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          side: ring(null),
          minimumSize: const WidgetStatePropertyAll(Size.square(48)),
          iconSize: const WidgetStatePropertyAll(22),
          shape: const WidgetStatePropertyAll(CircleBorder()),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: NafirColors.primary,
        foregroundColor: NafirColors.onPrimary,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NafirRadii.lg),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.surfaceContainerHighest,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(NafirRadii.xs),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? colors.outline
              : colors.outlineVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: NafirColors.transparent,
        modalBackgroundColor: colors.surfaceContainerHigh,
        modalBarrierColor: NafirColors.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NafirRadii.sheet)),
        ),
        showDragHandle: true,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(NafirRadii.xs),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: colors.onInverseSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: NafirMotion.tooltipWait,
      ),
    );
  }
}
