import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// The chat wallpaper: comic halftone dots, speed lines, and boxy outlined
/// doodles with offset shadows — winged halos, starbursts, sparkles and little
/// comic panels — in Serafim's ink-and-paper style.
///
/// Drawn in code from the active [AppPalette], so it is crisp at any size and
/// follows light/dark automatically. It is deliberately low-contrast: message
/// bubbles are opaque and always win.
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // Static art: cache it as one layer so scrolling messages never repaint it.
    return RepaintBoundary(
      child: CustomPaint(
        painter: ChatBackgroundPainter(AppColors.palette),
        size: Size.infinite,
      ),
    );
  }
}

class ChatBackgroundPainter extends CustomPainter {
  const ChatBackgroundPainter(this.palette);

  final AppPalette palette;

  bool get _light => palette.brightness == Brightness.light;

  /// Doodle outlines.
  Color get _ink => (_light ? palette.primaryDeep : palette.primaryPale)
      .withValues(alpha: _light ? 0.24 : 0.22);

  /// The offset "comic print" shadow under each doodle.
  Color get _shadow => (_light ? palette.line : palette.primary).withValues(
    alpha: _light ? 0.10 : 0.12,
  );

  Color get _rust => palette.rust.withValues(alpha: _light ? 0.24 : 0.22);
  Color get _teal => palette.teal.withValues(alpha: _light ? 0.26 : 0.24);
  Color get _dots => palette.primary.withValues(alpha: _light ? 0.16 : 0.13);
  Color get _rays => (_light ? palette.primaryDeep : palette.primaryPale)
      .withValues(alpha: _light ? 0.035 : 0.04);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.paper);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    _speedLines(canvas, size);
    _halftone(canvas, size, corner: Offset(size.width, 0), strength: 1);
    _halftone(canvas, size, corner: Offset(0, size.height), strength: 0.7);
    _doodles(canvas, size);

    canvas.restore();
  }

  // ---- comic action lines fanning out from the top-left corner ----
  void _speedLines(Canvas canvas, Size size) {
    final paint = Paint()..color = _rays;
    const origin = Offset(-20, -20);
    final reach = size.longestSide * 1.6;
    const count = 26;
    for (var i = 0; i < count; i++) {
      // Slightly uneven spacing, like hand-inked lines.
      final a = (i / count) * (math.pi / 2) + (i.isEven ? 0.01 : -0.008);
      final w = i % 4 == 0 ? 0.02 : 0.008;
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(
          origin.dx + reach * math.cos(a - w),
          origin.dy + reach * math.sin(a - w),
        )
        ..lineTo(
          origin.dx + reach * math.cos(a + w),
          origin.dy + reach * math.sin(a + w),
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  // ---- halftone dots, biggest at [corner], fading away from it ----
  void _halftone(
    Canvas canvas,
    Size size, {
    required Offset corner,
    required double strength,
  }) {
    const spacing = 13.0;
    final reach = size.shortestSide * 1.1;
    final paint = Paint()..color = _dots;

    final rows = (size.height / (spacing * 0.866)).ceil() + 1;
    final cols = (size.width / spacing).ceil() + 1;
    for (var row = 0; row < rows; row++) {
      final y = row * spacing * 0.866;
      final shift = row.isOdd ? spacing / 2 : 0.0;
      for (var col = 0; col < cols; col++) {
        final p = Offset(col * spacing + shift, y);
        final t = 1 - ((p - corner).distance / reach);
        if (t <= 0) continue;
        final radius = 4.4 * strength * math.pow(t, 1.5);
        if (radius < 0.5) continue;
        canvas.drawCircle(p, radius.toDouble(), paint);
      }
    }
  }

  // ---- scattered doodles on a jittered grid (stable: seeded per cell) ----
  void _doodles(Canvas canvas, Size size) {
    const cell = 132.0;
    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;

    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final rnd = math.Random((i * 73856093) ^ (j * 19349663) ^ 0x5e1a);
        if (rnd.nextDouble() < 0.28) continue; // breathing room

        final center = Offset(
          (i + 0.25 + rnd.nextDouble() * 0.5) * cell +
              (j.isOdd ? cell * 0.35 : 0),
          (j + 0.25 + rnd.nextDouble() * 0.5) * cell,
        );
        final angle = (rnd.nextDouble() - 0.5) * 0.7;
        final scale = 0.8 + rnd.nextDouble() * 0.35;
        final kind = rnd.nextInt(10);

        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        canvas.scale(scale);
        switch (kind) {
          case 0 || 1 || 2:
            _wingedHalo(canvas);
          case 3 || 4:
            _burst(canvas, accent: _rust);
          case 5 || 6:
            _sparkle(canvas, accent: _teal);
          case 7 || 8:
            _panel(canvas);
          default:
            _halo(canvas);
        }
        canvas.restore();
      }
    }
  }

  Paint get _stroke => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeJoin = StrokeJoin
        .miter // boxy, hard corners
    ..strokeCap = StrokeCap.butt
    ..color = _ink;

  Paint _stroked(Color c) => _stroke..color = c;

  /// Draws [path] twice: the offset print-shadow, then the outline.
  void _inked(
    Canvas canvas,
    Path path, {
    Color? color,
    bool fillShadow = true,
  }) {
    if (fillShadow) {
      canvas.drawPath(
        path.shift(const Offset(3.5, 3.5)),
        Paint()..color = _shadow,
      );
    }
    canvas.drawPath(path, _stroked(color ?? _ink));
  }

  /// Right wing, swept up and out, with stepped (boxy) feathers.
  Path _wing() => Path()
    ..moveTo(7, 4)
    ..lineTo(16, -18)
    ..lineTo(38, -38)
    ..lineTo(72, -50)
    ..lineTo(64, -37)
    ..lineTo(82, -34)
    ..lineTo(66, -24)
    ..lineTo(80, -15)
    ..lineTo(60, -10)
    ..lineTo(64, 0)
    ..lineTo(36, 2)
    ..lineTo(22, 12)
    ..close();

  void _wingedHalo(Canvas canvas) {
    final right = _wing();
    final left = _wing().transform(Matrix4.diagonal3Values(-1, 1, 1).storage);
    _inked(canvas, right);
    _inked(canvas, left);
    // Diamond body between the wings, with the halo floating above it.
    final body = Path()
      ..moveTo(0, -10)
      ..lineTo(9, 3)
      ..lineTo(0, 18)
      ..lineTo(-9, 3)
      ..close();
    _inked(canvas, body);
    final halo = Path()..addOval(const Rect.fromLTWH(-15, -27, 30, 9));
    _inked(canvas, halo, color: _rust.withValues(alpha: _light ? 0.4 : 0.34));
  }

  void _halo(Canvas canvas) {
    final outer = Path()..addOval(const Rect.fromLTWH(-26, -9, 52, 18));
    final inner = Path()..addOval(const Rect.fromLTWH(-18, -5, 36, 10));
    _inked(canvas, outer);
    canvas.drawPath(inner, _stroked(_ink));
  }

  /// Jagged comic "POW" burst.
  void _burst(Canvas canvas, {required Color accent}) {
    const points = 12;
    final path = Path();
    for (var k = 0; k < points * 2; k++) {
      final r = k.isEven ? 27.0 : 14.0;
      final a = (k / (points * 2)) * math.pi * 2 - math.pi / 2;
      final p = Offset(r * math.cos(a), r * math.sin(a));
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    _inked(canvas, path, color: accent);
    canvas.drawPath(
      Path()..addRect(const Rect.fromLTWH(-4, -4, 8, 8)),
      Paint()..color = accent.withValues(alpha: accent.a * 0.8),
    );
  }

  /// Four-point sparkle with a tiny companion plus-sign.
  void _sparkle(Canvas canvas, {required Color accent}) {
    final path = Path()
      ..moveTo(0, -22)
      ..lineTo(5, -5)
      ..lineTo(22, 0)
      ..lineTo(5, 5)
      ..lineTo(0, 22)
      ..lineTo(-5, 5)
      ..lineTo(-22, 0)
      ..lineTo(-5, -5)
      ..close();
    _inked(canvas, path, color: accent);

    final plus = Path()
      ..moveTo(30, -22)
      ..lineTo(30, -12)
      ..moveTo(25, -17)
      ..lineTo(35, -17);
    canvas.drawPath(plus, _stroked(_ink));
  }

  /// A little comic panel: boxy frame, hatching, and a corner tab.
  void _panel(Canvas canvas) {
    const rect = Rect.fromLTWH(-28, -20, 56, 40);
    final frame = Path()..addRect(rect);
    _inked(canvas, frame);

    final hatch = Path();
    for (var x = -14.0; x <= 20; x += 9) {
      hatch
        ..moveTo(x, 20)
        ..lineTo(x + 14, 6);
    }
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawPath(
      hatch,
      _stroked(_ink.withValues(alpha: _ink.a * 0.7))..strokeWidth = 1.5,
    );
    canvas.restore();

    canvas.drawPath(
      Path()..addRect(const Rect.fromLTWH(-28, -20, 14, 9)),
      Paint()..color = _ink.withValues(alpha: _ink.a * 0.6),
    );
  }

  @override
  bool shouldRepaint(ChatBackgroundPainter old) =>
      !identical(old.palette, palette);
}
