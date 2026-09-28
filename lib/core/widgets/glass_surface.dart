import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared visual language for Nafir's dark, glass-inspired surfaces.
abstract final class NafirGlass {
  static const background = Color(0xFF070810);
  static const surface = Color(0xFF121522);
  static const surfaceStrong = Color(0xFF191D2D);
  static const primary = Color(0xFFFF626A);
  static const secondary = Color(0xFF8D7CFF);
  static const border = Color(0x33FFFFFF);
  static const softBorder = Color(0x1FFFFFFF);
  static const shadow = Color(0x73000000);

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0xFF17101D),
      Color(0xFF090B14),
      Color(0xFF070810),
    ],
    stops: [0, 0.48, 1],
  );
}

/// Atmospheric background shared by primary app surfaces.
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

class _AmbientLight extends StatelessWidget {
  const _AmbientLight();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PositionedDirectional(
          top: -170,
          end: -110,
          child: _Glow(
            size: 390,
            color: NafirGlass.primary.withValues(alpha: 0.13),
          ),
        ),
        PositionedDirectional(
          bottom: 40,
          start: -150,
          child: _Glow(
            size: 420,
            color: NafirGlass.secondary.withValues(alpha: 0.11),
          ),
        ),
      ],
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
            (tint ?? Colors.white).withValues(alpha: 0.12),
            NafirGlass.surface.withValues(alpha: 0.78),
          ],
        ),
        border: Border.all(color: borderColor ?? NafirGlass.border),
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: NafirGlass.shadow,
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
