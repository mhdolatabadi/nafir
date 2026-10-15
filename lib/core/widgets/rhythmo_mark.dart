import 'package:flutter/material.dart';
import 'package:rhythmo/core/design/design.dart';

/// The rhythmo logo mark: a geometric lowercase r in ember with two violet
/// beat dots, on the app icon's dark tile. It is drawn from the same 512-unit
/// geometry as tool/generate_icons.py, so it matches the launcher icon.
class RhythmoMark extends StatelessWidget {
  const RhythmoMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ریتمو',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: RhythmoColors.markTile,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: RhythmoColors.softBorder),
          boxShadow: [
            BoxShadow(
              color: RhythmoColors.primary.withValues(alpha: 0.18),
              offset: const Offset(0, 8),
              blurRadius: 22,
            ),
          ],
        ),
        child: CustomPaint(painter: const RhythmoMarkPainter()),
      ),
    );
  }
}

/// Paints the r monogram scaled to fit its canvas, without a background.
class RhythmoMarkPainter extends CustomPainter {
  const RhythmoMarkPainter();

  // Geometry on the 512-unit icon grid, shared with tool/generate_icons.py.
  static const double _grid = 512;
  static const double _stem = 34;
  static const double _outer = 132;
  static const double _inner = 64;
  static const double _dot = 32;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _grid;
    canvas.save();
    canvas.translate(
      (size.width - _grid * scale) / 2,
      (size.height - _grid * scale) / 2,
    );
    canvas.scale(scale);

    final letter = Path()
      // Stem: a rounded equalizer bar.
      ..addRRect(
          RRect.fromLTRBR(135, 145, 203, 377, const Radius.circular(_stem)))
      // Shoulder: a quarter ring ending in a round cap.
      ..moveTo(135, 267)
      ..arcToPoint(const Offset(267, 135),
          radius: const Radius.circular(_outer))
      ..arcToPoint(const Offset(267, 203), radius: const Radius.circular(_stem))
      ..arcToPoint(
        const Offset(203, 267),
        radius: const Radius.circular(_inner),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(letter, Paint()..color = RhythmoColors.primary);

    final dot = Paint()..color = RhythmoColors.secondary;
    canvas.drawCircle(const Offset(345, 189), _dot, dot);
    canvas.drawCircle(
      const Offset(345, 283),
      _dot,
      Paint()..color = RhythmoColors.secondary.withValues(alpha: 0.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(RhythmoMarkPainter oldDelegate) => false;
}
