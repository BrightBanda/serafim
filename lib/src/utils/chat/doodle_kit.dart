import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// The pens a doodle is drawn with: one marker-weight line with round ends,
/// solid dots, and a few *very* faint tints. The tints are deliberately close
/// to invisible: they hint at a color without pulling the eye off the chat.
class DoodleInk {
  DoodleInk(AppPalette p)
    : bg = Paint()
        ..style = PaintingStyle.fill
        ..color = p.paper,
      bgStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2
        ..color = p.paper,
      line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _tone(
          p,
        ).withValues(alpha: p.brightness == Brightness.light ? 0.20 : 0.15),
      dot = Paint()
        ..style = PaintingStyle.fill
        ..color = _tone(
          p,
        ).withValues(alpha: p.brightness == Brightness.light ? 0.20 : 0.15),
      pink = _tint(const Color(0xFFF08FC0), p),
      mint = _tint(const Color(0xFF6FD3C0), p),
      lemon = _tint(const Color(0xFFF4D35E), p);

  /// Bold, fully coloured ink for stickers: the same drawings as the
  /// wallpaper, but meant to be looked at rather than ignored.
  DoodleInk.sticker()
    : bg = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white,
      bgStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2
        ..color = Colors.white,
      line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF1C2440),
      dot = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF1C2440),
      pink = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFF59AC6),
      mint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF7FDCC9),
      lemon = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFF7D96B);

  static Color _tone(AppPalette p) =>
      p.brightness == Brightness.light ? p.primaryDeep : p.primaryPale;

  static Paint _tint(Color c, AppPalette p) => Paint()
    ..style = PaintingStyle.fill
    ..color = c.withValues(
      alpha: p.brightness == Brightness.light ? 0.10 : 0.07,
    );

  final Paint bg; // the wallpaper color, to hide lines behind a shape
  final Paint
  bgStroke; // wallpaper-colored line, to knock out a gap in a stroke
  final Paint line; // outlines
  final Paint dot; // solid ink: pupils, sprinkles
  final Paint pink; // tongues, ice cream, cheeks
  final Paint mint; // drinks, a second tint
  final Paint lemon; // banana, cheese

  /// Draws with a different line weight for one call, then restores it.
  void thin(double w, void Function() body) {
    final old = line.strokeWidth;
    line.strokeWidth = w;
    body();
    line.strokeWidth = old;
  }
}

typedef DoodleDraw = void Function(Canvas c, DoodleInk ink);

class Doodle {
  const Doodle(this.name, this.draw, {this.filler = false});
  final String name;
  final DoodleDraw draw;

  /// Fillers are small shapes that go in the gaps between the big doodles.
  final bool filler;
}

/// Where a doodle's ink actually is, measured from its rendering (see
/// `test/doodle_bounds_test.dart`): the centre of its extent and the radius of
/// a circle around that centre that contains all of it. Packing uses these, so
/// two doodles can never touch.
class DoodleBounds {
  const DoodleBounds(this.cx, this.cy, this.radius);
  final double cx;
  final double cy;
  final double radius;
}

// ---------------------------------------------------------------- helpers ---

Path spiralPath(
  Offset c,
  double r0,
  double r1,
  double turns, {
  double start = 0,
}) {
  final path = Path();
  const steps = 48;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final a = start + t * turns * 2 * math.pi;
    final r = r0 + (r1 - r0) * t;
    final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path;
}

Path polyPath(List<Offset> pts, {bool close = true}) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final o in pts.skip(1)) {
    p.lineTo(o.dx, o.dy);
  }
  return close ? (p..close()) : p;
}

Path wavePath(Offset from, double width, double amp, int humps) {
  final p = Path()..moveTo(from.dx, from.dy);
  final w = width / humps;
  for (var i = 0; i < humps; i++) {
    final x0 = from.dx + i * w;
    p.quadraticBezierTo(x0 + w / 4, from.dy - amp, x0 + w / 2, from.dy);
    p.quadraticBezierTo(x0 + 3 * w / 4, from.dy + amp, x0 + w, from.dy);
  }
  return p;
}

Path teardropPath(Offset tip, double h, double w) {
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..quadraticBezierTo(tip.dx + w, tip.dy + h * 0.7, tip.dx, tip.dy + h)
    ..quadraticBezierTo(tip.dx - w, tip.dy + h * 0.7, tip.dx, tip.dy);
}

void eyeAt(
  Canvas c,
  DoodleInk ink,
  Offset at,
  double r,
  Offset pupilShift,
  double pupilR,
) {
  c.drawCircle(at, r, ink.line);
  c.drawCircle(at + pupilShift, pupilR, ink.dot);
}

void sparkleAt(Canvas c, DoodleInk ink, Offset at, double r) {
  final p = Path()
    ..moveTo(at.dx, at.dy - r)
    ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
    ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
    ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
    ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r);
  ink.thin(1.4, () => c.drawPath(p, ink.line));
}

/// Two dot eyes.
void dotEyes(
  Canvas c,
  DoodleInk ink, {
  double y = 0,
  double dx = 6,
  double r = 1.5,
}) {
  c.drawCircle(Offset(-dx, y), r, ink.dot);
  c.drawCircle(Offset(dx, y), r, ink.dot);
}

/// A smile curve centred on x = 0.
void smile(
  Canvas c,
  DoodleInk ink, {
  double y = 0,
  double w = 6,
  double depth = 4,
}) {
  c.drawPath(
    Path()
      ..moveTo(-w, y)
      ..quadraticBezierTo(0, y + depth * 2, w, y),
    ink.line,
  );
}

void blush(Canvas c, DoodleInk ink, {double dx = 9, double y = 3}) {
  c.drawCircle(Offset(-dx, y), 2.0, ink.pink);
  c.drawCircle(Offset(dx, y), 2.0, ink.pink);
}
