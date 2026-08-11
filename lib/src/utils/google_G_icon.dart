import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A small, simplified rendering of the Google "G" mark used on the
/// "Continue with Google" button. Drawn as four colored arcs rather
/// than bundling an image asset, so this widget has no dependencies.
class GoogleGIcon extends StatelessWidget {
  const GoogleGIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = radius * 0.62;

    final paintFor = (Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four quarter-ish arcs approximating the Google pinwheel mark.
    canvas.drawArc(
      rect,
      _deg(-45),
      _deg(95),
      false,
      paintFor(const Color(0xFF4285F4)),
    );
    canvas.drawArc(
      rect,
      _deg(50),
      _deg(95),
      false,
      paintFor(const Color(0xFF34A853)),
    );
    canvas.drawArc(
      rect,
      _deg(145),
      _deg(70),
      false,
      paintFor(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(
      rect,
      _deg(215),
      _deg(70),
      false,
      paintFor(const Color(0xFFEA4335)),
    );
  }

  double _deg(double degrees) => degrees * math.pi / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
