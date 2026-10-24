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
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = haloColor
      ..style = PaintingStyle.fill;
    // Three feathers fanning out from the shoulder, longest on top.
    for (var i = 0; i < 3; i++) {
      final lift = i * 0.28;
      final path = Path()
        ..moveTo(w * 0.05, h * (0.95 - lift * 0.3))
        ..quadraticBezierTo(
          w * 0.30,
          h * (0.55 - lift),
          w * (0.98 - i * 0.10),
          h * (0.10 + lift * 0.9),
        )
        ..quadraticBezierTo(
          w * 0.62,
          h * (0.62 - lift * 0.5),
          w * 0.05,
          h * (0.95 - lift * 0.3),
        )
        ..close();
      canvas.drawPath(
        path,
        paint..color = haloColor.withValues(alpha: 1 - i * 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(_WingPainter old) => false;
}
