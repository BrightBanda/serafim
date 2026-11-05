import 'package:flutter/material.dart';

/// The Echo mark, ((•)): a dot with two arcs on each side, the same drawing
/// as in the Echos promo video.
class EchoIcon extends StatelessWidget {
  const EchoIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _EchoPainter(
        color ?? IconTheme.of(context).color ?? Colors.white,
      ),
    ),
  );
}

class _EchoPainter extends CustomPainter {
  _EchoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on the promo's 24 × 24 grid.
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(const Offset(12, 12), 2.4, Paint()..color = color);
    void arc(Offset from, Offset to, double r) => canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..arcToPoint(to, radius: Radius.circular(r)),
      stroke,
    );
    arc(const Offset(8.2, 15.8), const Offset(8.2, 8.2), 5.4);
    arc(const Offset(15.8, 8.2), const Offset(15.8, 15.8), 5.4);
    arc(const Offset(5.4, 18.6), const Offset(5.4, 5.4), 9.4);
    arc(const Offset(18.6, 5.4), const Offset(18.6, 18.6), 9.4);
  }

  @override
  bool shouldRepaint(_EchoPainter old) => old.color != color;
}
