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
  // The light drifts once as the screen opens, then rests: a blur that
  // moves forever costs battery on every frame and never lets the UI
  // settle.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduced motion: show the resting position straight away.
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

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
                  color: Colors.white.withValues(alpha: 0.045),
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
            (tint ?? Colors.white).withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.055),
            NafirGlass.surface.withValues(alpha: 0.72),
          ],
          stops: const [0, 0.45, 1],
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
