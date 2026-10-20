import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

/// Paints strokes (and, when [image] is given, the picture under them).
///
/// [scale] multiplies every point and width, so the same painter draws the
/// on-screen preview (scale 1) and the full-size export.
class StrokePainter extends CustomPainter {
  StrokePainter({required this.strokes, this.image, this.scale = 1});

  final List<Stroke> strokes;
  final ui.Image? image;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img != null) canvas.drawImage(img, Offset.zero, Paint());
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width * scale
        ..isAntiAlias = true;
      final pts = [for (final p in s.points) p * scale];
      if (pts.length == 1) {
        // A tap: a dot.
        canvas.drawCircle(
          pts.first,
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length - 1; i++) {
        // Quadratic curves through the midpoints make the line smooth.
        final mid = (pts[i] + pts[i + 1]) / 2;
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(StrokePainter old) => true;
}

/// Draws [strokes] onto [image] at the picture's full size and returns PNG
/// bytes. [displayedWidth] is how wide the picture was on screen.
Future<Uint8List> flattenStrokes(
  ui.Image image,
  List<Stroke> strokes, {
  required double displayedWidth,
}) async {
  final recorder = ui.PictureRecorder();
  final size = Size(image.width.toDouble(), image.height.toDouble());
  StrokePainter(
    strokes: strokes,
    image: image,
    scale: strokeScale(displayedWidth: displayedWidth, imageWidth: image.width),
  ).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final out = await picture.toImage(image.width, image.height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
