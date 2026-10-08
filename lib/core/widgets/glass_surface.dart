import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nafir/core/design/tokens.dart';

/// The glass colours under their original names. New code reads
/// [NafirColors] from lib/core/design/tokens.dart instead.
abstract final class NafirGlass {
  static const background = NafirColors.background;
  static const surface = NafirColors.surface;
  static const surfaceStrong = NafirColors.surfaceStrong;
  static const primary = NafirColors.primary;
  static const secondary = NafirColors.secondary;
  static const border = NafirColors.border;
  static const softBorder = NafirColors.softBorder;
  static const shadow = NafirColors.shadow;

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      NafirColors.ambientTop,
      NafirColors.ambientMiddle,
      NafirColors.background,
    ],
    stops: [0, 0.48, 1],
  );
}

/// Atmospheric animated background shared by primary app surfaces.
class NafirBackdrop extends StatelessWidget {
  const NafirBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: NafirGlass.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: _AmbientLight()),
          child,
        ],
      ),
    );
  }
}

class _AmbientLight extends StatefulWidget {
  const _AmbientLight();

  @override
  State<_AmbientLight> createState() => _AmbientLightState();
}

class _AmbientLightState extends State<_AmbientLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NafirMotion.arrival,
  )..forward();

  late final Animation<double> _drift = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With reduced motion the light is simply in place.
    if (MediaQuery.maybeDisableAnimationsOf(context) == true &&
        _controller.isAnimating) {
      _controller.value = 1;
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _drift,
        builder: (context, _) {
          final value = _drift.value;
          return Stack(
            children: [
              PositionedDirectional(
                top: -170 + (value * 28),
                end: -120 + (value * 22),
                child: Transform.scale(
                  scale: 1 + (value * 0.05),
                  child: _Glow(
                    size: 430,
                    color: NafirGlass.primary.withValues(alpha: 0.16),
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: 20 + (value * 26),
                start: -160 + (value * 18),
                child: Transform.scale(
                  scale: 1.04 - (value * 0.04),
                  child: _Glow(
                    size: 460,
                    color: NafirGlass.secondary.withValues(alpha: 0.14),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 170 - (value * 22),
                start: 30 + (value * 36),
                child: _Glow(
                  size: 260,
                  color: NafirColors.highlight.withValues(alpha: 0.045),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 72, sigmaY: 72),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// A bounded glass layer. Reserve blur for structural surfaces instead of
/// repeating it for every list row.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 20,
    this.blur = 18,
    this.tint,
    this.borderColor,
    this.shadow = true,
  });

  /// A surface at one of the glass levels in [NafirGlassLevel].
  GlassSurface.level(
    NafirGlassLevel level, {
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = NafirRadii.xl,
    this.tint,
  })  : blur = level.blur,
        borderColor = level.border,
        shadow = level.shadow;

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double blur;
  final Color? tint;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            (tint ?? NafirColors.highlight).withValues(alpha: 0.16),
            NafirColors.highlight.withValues(alpha: 0.055),
            NafirColors.surface.withValues(alpha: 0.72),
          ],
          stops: const [0, 0.45, 1],
        ),
        border: Border.all(color: borderColor ?? NafirColors.border),
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: NafirColors.shadow,
                  offset: Offset(0, 12),
                  blurRadius: 32,
                ),
              ]
            : null,
      ),
      child: child,
    );
    if (blur > 0) {
      surface = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: surface,
        ),
      );
    }
    return Padding(padding: margin ?? EdgeInsets.zero, child: surface);
  }
}
