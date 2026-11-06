import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/stickers/sticker_view.dart';

/// Paints strokes (and, when [image] is given, the picture under them).
///
/// [scale] multiplies every point and width, so the same painter draws the
/// on-screen preview (scale 1) and the full-size export.
class StrokePainter extends CustomPainter {
  StrokePainter({
    required this.strokes,
    this.image,
    this.scale = 1,
    this.drawing,
  });

  final List<Stroke> strokes;
  final ui.Image? image;
  final double scale;

  /// An earlier drawing being edited, stretched to fill the sheet. Unlike
  /// [image] it belongs to the ink: an eraser can rub it out.
  final ui.Image? drawing;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img != null) canvas.drawImage(img, Offset.zero, Paint());

    // The pen strokes live in a layer of their own, so an eraser stroke clears
    // them and nothing else — never the picture or paper underneath.
    final needsLayer = strokes.any((s) => s.erase);
    if (needsLayer) canvas.saveLayer(Offset.zero & size, Paint());
    final old = drawing;
    if (old != null) {
      canvas.drawImageRect(
        old,
        Offset.zero & Size(old.width.toDouble(), old.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      if (s.sticker != null) {
        _paintSticker(canvas, s);
      } else if (s.brush == Brush.ink && !s.erase && s.points.length > 2) {
        _paintInk(canvas, s);
      } else {
        _paintLine(canvas, s);
      }
    }
    if (needsLayer) canvas.restore();
  }

  void _paintSticker(Canvas canvas, Stroke s) {
    final sticker = stickerById(s.sticker!);
    if (sticker == null) return; // from a newer version of the app
    final side = s.stickerSize * scale;
    canvas.save();
    canvas.translate(s.points.first.dx * scale, s.points.first.dy * scale);
    canvas.rotate(s.stickerRotation);
    canvas.translate(-side / 2, -side / 2);
    StickerPainter(sticker).paint(canvas, Size.square(side));
    canvas.restore();
  }

  void _paintLine(Canvas canvas, Stroke s) {
    final (widthBy, opacity, cap) = s.erase
        ? (1.0, 1.0, StrokeCap.round)
        : switch (s.brush) {
            Brush.marker => (1.6, 0.85, StrokeCap.square),
            Brush.highlighter => (3.2, 0.38, StrokeCap.butt),
            _ => (1.0, 1.0, StrokeCap.round),
          };
    final paint = Paint()
      ..color = s.color.withValues(alpha: s.color.a * opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.width * widthBy * scale
      ..isAntiAlias = true;
    if (s.erase) paint.blendMode = BlendMode.clear;
    final pts = [for (final p in s.points) p * scale];
    if (pts.length == 1) {
      // A tap: a dot.
      canvas.drawCircle(
        pts.first,
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
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

  /// A line whose thickness follows how it was drawn. Worked out from the
  /// points alone, so it looks the same on both phones.
  void _paintInk(Canvas canvas, Stroke s) {
    final pts = [for (final p in s.points) p * scale];
    final span = s.width * scale * 2.5; // a step this long is "fast"
    final paint = Paint()
      ..color = s.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    const tapered = 10;
    final last = pts.length - 1;

    // How thick the line is at each point.
    final widths = List<double>.filled(pts.length, 0);
    var weight = 0.6;
    for (var i = 1; i <= last; i++) {
      final step = (pts[i] - pts[i - 1]).distance;
      final slow = 1.25 - (step / span).clamp(0.0, 1.0) * 0.8;
      weight += (slow - weight) * 0.25;
      final ends = math.min(i, last - i);
      final taper = 0.35 + 0.65 * (ends / tapered).clamp(0.0, 1.0);
      widths[i] = s.width * scale * weight * taper;
    }
    widths[0] = widths[1];

    // Along the same curve as the other brushes, in steps short enough that
    // the thickness changes smoothly and the edge shows no bumps.
    var from = pts.first;
    for (var i = 1; i < last; i++) {
      final end = i == last - 1 ? pts[last] : (pts[i] + pts[i + 1]) / 2;
      final start = from;
      final length = (end - start).distance;
      final steps = (length / 1.5).ceil().clamp(1, 12);
      for (var k = 1; k <= steps; k++) {
        final t = k / steps;
        final u = 1 - t;
        final at = start * (u * u) + pts[i] * (2 * u * t) + end * (t * t);
        canvas.drawLine(
          from,
          at,
          paint..strokeWidth = widths[i - 1] + (widths[i] - widths[i - 1]) * t,
        );
        from = at;
      }
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
