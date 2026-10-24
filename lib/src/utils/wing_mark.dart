import 'package:flutter/material.dart';
import 'package:serafim/src/utils/halo_style.dart';

/// A tiny gold wing: the mark of someone in your Wings.
class WingMark extends StatelessWidget {
  const WingMark({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'One of your Wings',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _WingPainter()),
      ),
    );
  }
}

class _WingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    double x(double v) => v * s;
    double y(double v) => v * s;

    // One solid silhouette, so it still reads as a wing at chat-list size:
    // a rounded shoulder on the left, and three broad tiers of feathers
    // stepping down to the right, the top one longest, each with a rounded
    // end. Separate thin feathers blur into fingers when small.
    final wing = Path()
      ..moveTo(x(0.04), y(0.96))
      // The leading edge: a long convex sweep from the shoulder up to a
      // pointed tip — the line that says "wing".
      ..cubicTo(x(0.00), y(0.48), x(0.36), y(0.08), x(0.98), y(0.02))
      // Top tier: from the tip, a rounded end coming back underneath.
      ..quadraticBezierTo(x(0.94), y(0.22), x(0.74), y(0.30))
      // Step in, then the middle tier.
      ..lineTo(x(0.56), y(0.34))
      ..lineTo(x(0.80), y(0.44))
      ..quadraticBezierTo(x(0.78), y(0.60), x(0.58), y(0.64))
      // Step in, then the bottom tier.
      ..lineTo(x(0.42), y(0.66))
      ..lineTo(x(0.60), y(0.78))
      ..quadraticBezierTo(x(0.56), y(0.94), x(0.36), y(0.95))
      ..quadraticBezierTo(x(0.20), y(0.99), x(0.04), y(0.96))
      ..close();
    canvas.drawPath(wing, Paint()..color = haloColor);
  }

  @override
  bool shouldRepaint(_WingPainter old) => false;
}
