import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/doodle_kit.dart';

// Objects: some with faces, some just things. Local coordinates, roughly
// +-30 around (0, 0).

// ------------------------------------------------------------ with faces ---

/// A puffy cloud having a bad day: derpy face, a little rain.
void cloudFace(Canvas c, DoodleInk ink) {
  Path circle(double x, double y, double r) =>
      Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
  var cloud = circle(-12, -2, 9);
  cloud = Path.combine(PathOperation.union, cloud, circle(1, -8, 12));
  cloud = Path.combine(PathOperation.union, cloud, circle(14, -2, 9));
  cloud = Path.combine(
    PathOperation.union,
    cloud,
    Path()..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-21, -4, 43, 13),
        const Radius.circular(6),
      ),
    ),
  );
  c.drawPath(cloud, ink.mint);
  c.drawPath(cloud, ink.line);
  c.drawCircle(const Offset(-6, -3), 1.7, ink.dot);
  eyeAt(c, ink, const Offset(7, -3), 3.4, const Offset(0.8, 0.4), 1.3);
  c.drawPath(
    Path()
      ..moveTo(-5, 3)
      ..quadraticBezierTo(0, 7, 6, 2.5),
    ink.line,
  );
  for (final x in const [-9.0, 0.0, 9.0]) {
    c.drawPath(teardropPath(Offset(x, 14), 6, 1.8), ink.line);
  }
}

/// A sun too cool for the sky.
void coolSun(Canvas c, DoodleInk ink) {
  c.drawCircle(Offset.zero, 12, ink.lemon);
  c.drawCircle(Offset.zero, 12, ink.line);
  for (var i = 0; i < 10; i++) {
    final a = i / 10 * 2 * math.pi;
    final r0 = i.isEven ? 16.0 : 16.0, r1 = i.isEven ? 24.0 : 21.0;
    c.drawLine(
      Offset(r0 * math.cos(a), r0 * math.sin(a)),
      Offset(r1 * math.cos(a), r1 * math.sin(a)),
      ink.line,
    );
  }
  // Sunglasses.
  final l = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-10, -5, 8, 6),
    const Radius.circular(2),
  );
  final r = RRect.fromRectAndRadius(
    const Rect.fromLTWH(2, -5, 8, 6),
    const Radius.circular(2),
  );
  c.drawRRect(l, ink.dot);
  c.drawRRect(r, ink.dot);
  c.drawLine(const Offset(-2, -3), const Offset(2, -3), ink.line);
  smile(c, ink, y: 5, w: 5, depth: 2.2);
}

/// A crescent moon already in bed.
void sleepyMoon(Canvas c, DoodleInk ink) {
  final moon = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 18)),
    Path()..addOval(Rect.fromCircle(center: const Offset(10, -5), radius: 15)),
  );
  c.drawPath(moon, ink.lemon);
  c.drawPath(moon, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-9, -1)
      ..quadraticBezierTo(-6, 2.5, -3, -1),
    ink.line,
  );
  c.drawCircle(const Offset(-8, 7), 1.2, ink.pink);
  c.drawPath(
    Path()
      ..moveTo(-8, 10)
      ..quadraticBezierTo(-4.5, 12.5, -1, 10),
    ink.line,
  );
  sparkleAt(c, ink, const Offset(14, -14), 4);
  sparkleAt(c, ink, const Offset(20, 6), 3);
  c.drawPath(
    polyPath([
      const Offset(14, 14),
      const Offset(21, 14),
      const Offset(14, 22),
      const Offset(21, 22),
    ], close: false),
    ink.line..strokeWidth = 1.4,
  );
  ink.line.strokeWidth = 1.8;
}

/// A cactus in a pot, small flower on top, very pleased with itself.
void cactusFace(Canvas c, DoodleInk ink) {
  // Arms behind the body.
  c.drawPath(
    Path()
      ..moveTo(-8, 4)
      ..lineTo(-15, 4)
      ..quadraticBezierTo(-19, 4, -19, 0)
      ..lineTo(-19, -9),
    ink.line..strokeWidth = 5.5,
  );
  c.drawPath(
    Path()
      ..moveTo(8, 8)
      ..lineTo(15, 8)
      ..quadraticBezierTo(19, 8, 19, 4)
      ..lineTo(19, -5),
    ink.line..strokeWidth = 5.5,
  );
  ink.line.strokeWidth = 1.8;
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-9, -20, 18, 34),
    const Radius.circular(9),
  );
  c.drawRRect(body, ink.bg);
  c.drawRRect(body, ink.mint);
  c.drawRRect(body, ink.line);
  dotEyes(c, ink, y: -8, dx: 3.6, r: 1.3);
  smile(c, ink, y: -2, w: 3.4, depth: 1.6);
  blush(c, ink, dx: 5.5, y: -4);
  // Flower.
  for (var i = 0; i < 5; i++) {
    final a = i / 5 * 2 * math.pi;
    c.drawCircle(
      Offset(3.2 * math.cos(a), -22 + 3.2 * math.sin(a)),
      1.9,
      ink.pink,
    );
  }
  c.drawCircle(const Offset(0, -22), 1.4, ink.dot);
  // Pot.
  final pot = polyPath(const [
    Offset(-12, 12),
    Offset(12, 12),
    Offset(9, 27),
    Offset(-9, 27),
  ]);
  c.drawPath(pot, ink.bg);
  c.drawPath(pot, ink.lemon);
  c.drawPath(pot, ink.line);
  c.drawLine(
    const Offset(-14, 12),
    const Offset(14, 12),
    ink.line..strokeWidth = 2.6,
  );
  ink.line.strokeWidth = 1.8;
}

/// A cupcake, wearing its cherry like a hat.
void cupcake(Canvas c, DoodleInk ink) {
  final wrap = polyPath(const [
    Offset(-14, 2),
    Offset(14, 2),
    Offset(10, 22),
    Offset(-10, 22),
  ]);
  c.drawPath(wrap, ink.lemon);
  c.drawPath(wrap, ink.line);
  for (final x in const [-8.0, -2.7, 2.7, 8.0]) {
    c.drawLine(
      Offset(x * 1.0, 4),
      Offset(x * 0.75, 20),
      ink.line..strokeWidth = 1.1,
    );
  }
  ink.line.strokeWidth = 1.8;
  final cream = Path()
    ..moveTo(-16, 2)
    ..quadraticBezierTo(-20, -8, -9, -9)
    ..quadraticBezierTo(-10, -18, 0, -17)
    ..quadraticBezierTo(10, -18, 9, -9)
    ..quadraticBezierTo(20, -8, 16, 2)
    ..close();
  c.drawPath(cream, ink.pink);
  c.drawPath(cream, ink.line);
  c.drawCircle(const Offset(0, -21), 3.2, ink.pink);
  c.drawCircle(const Offset(0, -21), 3.2, ink.line);
  c.drawLine(const Offset(0, -24), const Offset(3, -29), ink.line);
  eyeAt(c, ink, const Offset(-6, -6), 3, const Offset(0.6, 0.5), 1.2);
  eyeAt(c, ink, const Offset(6, -6), 3, const Offset(-0.6, 0.5), 1.2);
  smile(c, ink, y: -1, w: 3.5, depth: 1.8);
}

/// A mug of coffee with steam and opinions.
void coffeeMug(Canvas c, DoodleInk ink) {
  final mug = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-16, -6, 28, 28),
    const Radius.circular(5),
  );
  c.drawRRect(mug, ink.lemon);
  c.drawRRect(mug, ink.line);
  c.drawArc(
    const Rect.fromLTWH(6, 1, 15, 15),
    -math.pi / 2,
    math.pi,
    false,
    ink.line,
  );
  c.drawLine(const Offset(-16, 0), const Offset(12, 0), ink.line);
  dotEyes(c, ink, y: 9, dx: 5);
  c.translate(-2, 0);
  smile(c, ink, y: 14, w: 4, depth: 2);
  c.translate(2, 0);
  for (final x in const [-9.0, -2.0, 5.0]) {
    c.drawPath(
      Path()
        ..moveTo(x, -9)
        ..quadraticBezierTo(x - 4, -14, x, -18)
        ..quadraticBezierTo(x + 4, -22, x, -26),
      ink.line,
    );
  }
}

/// A burger that is delighted to be eaten.
void burger(Canvas c, DoodleInk ink) {
  final top = Path()
    ..moveTo(-20, -4)
    ..quadraticBezierTo(-20, -22, 0, -22)
    ..quadraticBezierTo(20, -22, 20, -4)
    ..close();
  c.drawPath(top, ink.lemon);
  c.drawPath(top, ink.line);
  for (final p in const [
    Offset(-10, -14),
    Offset(-1, -17),
    Offset(9, -14),
    Offset(3, -10),
  ]) {
    c.drawLine(p, p + const Offset(2.4, 1), ink.line..strokeWidth = 1.5);
  }
  ink.line.strokeWidth = 1.8;
  c.drawPath(wavePath(const Offset(-21, -1), 42, 2, 5), ink.line);
  final patty = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-21, 3, 42, 7),
    const Radius.circular(3.5),
  );
  c.drawRRect(patty, ink.pink);
  c.drawRRect(patty, ink.line);
  final bottom = Path()
    ..moveTo(-20, 13)
    ..lineTo(20, 13)
    ..quadraticBezierTo(20, 22, 11, 22)
    ..lineTo(-11, 22)
    ..quadraticBezierTo(-20, 22, -20, 13);
  c.drawPath(bottom, ink.lemon);
  c.drawPath(bottom, ink.line);
  dotEyes(c, ink, y: -8, dx: 6.5, r: 1.4);
  smile(c, ink, y: -4, w: 4, depth: 2);
}

/// A taco, loaded and loving it.
void taco(Canvas c, DoodleInk ink) {
  final shell = Path()
    ..moveTo(-24, 8)
    ..quadraticBezierTo(-24, -16, 0, -16)
    ..quadraticBezierTo(24, -16, 24, 8)
    ..close();
  c.drawPath(shell, ink.lemon);
  c.drawPath(shell, ink.line);
  c.drawPath(wavePath(const Offset(-23, 8), 46, 3, 6), ink.line);
  c.drawPath(
    Path()
      ..moveTo(-16, 3)
      ..quadraticBezierTo(0, -10, 16, 3),
    ink.line..strokeWidth = 1.2,
  );
  ink.line.strokeWidth = 1.8;
  dotEyes(c, ink, y: -5, dx: 6);
  smile(c, ink, y: 0, w: 4.5, depth: 2.2);
  blush(c, ink, dx: 11, y: -1);
  c.drawCircle(const Offset(-12, -22), 1.2, ink.dot);
  c.drawCircle(const Offset(14, -22), 1.2, ink.dot);
}

/// A lightbulb with an idea (and a face).
void lightbulb(Canvas c, DoodleInk ink) {
  final bulb = Path()
    ..moveTo(-8, 12)
    ..quadraticBezierTo(-8, 6, -13, 0)
    ..arcToPoint(
      const Offset(13, 0),
      radius: const Radius.circular(14),
      clockwise: true,
    )
    ..quadraticBezierTo(8, 6, 8, 12)
    ..close();
  c.drawPath(bulb, ink.lemon);
  c.drawPath(bulb, ink.line);
  c.drawLine(const Offset(-7, 16), const Offset(7, 16), ink.line);
  c.drawLine(const Offset(-5, 20), const Offset(5, 20), ink.line);
  dotEyes(c, ink, y: -4, dx: 4.6, r: 1.4);
  smile(c, ink, y: 1, w: 3.6, depth: 2);
  for (var i = 0; i < 5; i++) {
    final a =
        math.pi + i * math.pi / 4 + math.pi / 8 - math.pi / 2 + math.pi / 2;
    final dir = Offset(math.cos(a), math.sin(a));
    c.drawLine(
      const Offset(0, -6) + dir * 19,
      const Offset(0, -6) + dir * 25,
      ink.line,
    );
  }
}

/// A heart with feelings.
void heartFace(Canvas c, DoodleInk ink) {
  final p = Path()
    ..moveTo(0, 22)
    ..cubicTo(-34, -2, -16, -24, 0, -9)
    ..cubicTo(16, -24, 34, -2, 0, 22);
  c.drawPath(p, ink.pink);
  c.drawPath(p, ink.line);
  dotEyes(c, ink, y: -1, dx: 6);
  smile(c, ink, y: 5, w: 4.5, depth: 2.4);
  blush(c, ink, dx: 11, y: 4);
  c.drawLine(const Offset(-20, -19), const Offset(-24, -24), ink.line);
  c.drawLine(const Offset(-14, -22), const Offset(-16, -28), ink.line);
}

/// A star that knows it is a star.
void starFace(Canvas c, DoodleInk ink) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? 24.0 : 11.0;
    final a = -math.pi / 2 + i * math.pi / 5;
    final o = Offset(r * math.cos(a), r * math.sin(a) + 1);
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  p.close();
  c.drawPath(p, ink.lemon);
  c.drawPath(p, ink.line);
  dotEyes(c, ink, y: 0, dx: 5, r: 1.5);
  smile(c, ink, y: 5, w: 4, depth: 2);
  sparkleAt(c, ink, const Offset(24, -18), 4);
}

/// A mushroom cap, spots and all.
void mushroom(Canvas c, DoodleInk ink) {
  final cap = Path()
    ..moveTo(-24, 4)
    ..quadraticBezierTo(-24, -22, 0, -22)
    ..quadraticBezierTo(24, -22, 24, 4)
    ..close();
  c.drawPath(cap, ink.pink);
  c.drawPath(cap, ink.line);
  final stem = Path()
    ..moveTo(-9, 4)
    ..quadraticBezierTo(-12, 20, -14, 22)
    ..lineTo(14, 22)
    ..quadraticBezierTo(12, 20, 9, 4);
  c.drawPath(stem, ink.bg);
  c.drawPath(stem, ink.line);
  for (final s in const [
    [Offset(-12, -8), 4.0],
    [Offset(6, -12), 3.2],
    [Offset(14, -3), 2.6],
    [Offset(-3, -3), 2.2],
  ]) {
    c.drawCircle(s[0] as Offset, s[1] as double, ink.line..strokeWidth = 1.3);
  }
  ink.line.strokeWidth = 1.8;
  dotEyes(c, ink, y: 12, dx: 4);
  smile(c, ink, y: 16, w: 3, depth: 1.6);
}

/// A wedge of cheese with a face in one of its holes.
void cheese(Canvas c, DoodleInk ink) {
  final wedge = polyPath(const [
    Offset(-22, 10),
    Offset(22, 10),
    Offset(22, -2),
    Offset(-22, -16),
  ]);
  c.drawPath(wedge, ink.lemon);
  c.drawPath(wedge, ink.line);
  c.drawLine(const Offset(-22, 10), const Offset(-22, 2), ink.line);
  c.drawPath(
    polyPath(const [
      Offset(-22, 10),
      Offset(-22, 2),
      Offset(22, 2),
    ], close: false),
    ink.line..strokeWidth = 1.2,
  );
  ink.line.strokeWidth = 1.8;
  c.drawCircle(const Offset(-10, -2), 3, ink.line);
  c.drawCircle(const Offset(8, -6), 2.4, ink.line);
  c.drawCircle(const Offset(14, 6), 2, ink.line);
  dotEyes(c, ink, y: 5, dx: 3.2, r: 1.2);
  c.translate(-1, 0);
  smile(c, ink, y: 7.5, w: 3, depth: 1.3);
  c.translate(1, 0);
  // A mouse, looking hopeful.
  c.drawCircle(const Offset(-20, 19), 3.5, ink.line);
  c.drawCircle(const Offset(-23, 16), 1.8, ink.line);
  c.drawCircle(const Offset(-17, 16), 1.8, ink.line);
}

/// An apple with a bite and a worm who regrets nothing.
void appleWorm(Canvas c, DoodleInk ink) {
  final apple = Path()
    ..moveTo(0, -12)
    ..cubicTo(-10, -20, -26, -10, -22, 6)
    ..cubicTo(-19, 22, -6, 24, 0, 20)
    ..cubicTo(6, 24, 19, 22, 22, 6)
    ..cubicTo(26, -10, 10, -20, 0, -12);
  c.drawPath(apple, ink.pink);
  c.drawPath(apple, ink.line);
  c.drawPath(
    Path()
      ..moveTo(0, -12)
      ..quadraticBezierTo(1, -18, 5, -22),
    ink.line,
  );
  final leaf = Path()
    ..moveTo(3, -17)
    ..quadraticBezierTo(10, -26, 17, -20)
    ..quadraticBezierTo(10, -14, 3, -17);
  c.drawPath(leaf, ink.mint);
  c.drawPath(leaf, ink.line);
  // Worm peeking out.
  final worm = Path()
    ..moveTo(10, 4)
    ..quadraticBezierTo(24, 4, 22, -6)
    ..quadraticBezierTo(21, -12, 27, -13);
  // A tube: outline stroke, then a paper-colored stroke inside it.
  c.drawPath(worm, ink.line..strokeWidth = 5.2);
  c.drawPath(worm, ink.bgStroke..strokeWidth = 2.2);
  ink.line.strokeWidth = 1.8;
  c.drawCircle(const Offset(27, -13), 3.4, ink.bg);
  c.drawCircle(const Offset(27, -13), 3.4, ink.line);
  c.drawCircle(const Offset(26, -14), 0.8, ink.dot);
  c.drawCircle(const Offset(28.6, -14), 0.8, ink.dot);
}

/// A balloon with a string and a worried look.
void balloon(Canvas c, DoodleInk ink) {
  final b = Path()
    ..moveTo(0, 18)
    ..cubicTo(-26, 6, -20, -24, 0, -24)
    ..cubicTo(20, -24, 26, 6, 0, 18);
  c.drawPath(b, ink.pink);
  c.drawPath(b, ink.line);
  c.drawPath(
    polyPath(const [Offset(0, 18), Offset(-3, 22), Offset(3, 22)]),
    ink.line,
  );
  c.drawPath(
    Path()
      ..moveTo(0, 22)
      ..quadraticBezierTo(-8, 27, 0, 31)
      ..quadraticBezierTo(8, 35, 0, 39),
    ink.line,
  );
  c.drawArc(
    const Rect.fromLTWH(-14, -18, 10, 14),
    math.pi * 1.1,
    math.pi * 0.5,
    false,
    ink.line,
  );
  dotEyes(c, ink, y: -4, dx: 5.5, r: 1.5);
  c.drawOval(
    Rect.fromCenter(center: const Offset(0, 5), width: 5, height: 6),
    ink.line,
  );
}

/// A ringed planet who is just happy to be here.
void planet(Canvas c, DoodleInk ink) {
  c.drawCircle(Offset.zero, 14, ink.lemon);
  c.drawCircle(Offset.zero, 14, ink.line);
  dotEyes(c, ink, y: -2, dx: 5, r: 1.5);
  smile(c, ink, y: 3, w: 4, depth: 2);
  c.save();
  c.rotate(-0.35);
  // Back half of the ring, hidden by the planet; front half drawn over it.
  c.drawArc(const Rect.fromLTWH(-27, -7, 54, 14), 0, math.pi, false, ink.line);
  c.drawArc(
    const Rect.fromLTWH(-27, -7, 54, 14),
    math.pi,
    math.pi * 0.28,
    false,
    ink.line,
  );
  c.drawArc(
    const Rect.fromLTWH(-27, -7, 54, 14),
    math.pi * 1.72,
    math.pi * 0.28,
    false,
    ink.line,
  );
  c.restore();
  sparkleAt(c, ink, const Offset(-22, -18), 3.6);
  c.drawCircle(const Offset(22, -17), 1.4, ink.dot);
}

/// Toast with butter, smiling at its own breakfast.
void toast(Canvas c, DoodleInk ink) {
  final t = Path()
    ..moveTo(-18, 20)
    ..lineTo(-18, -4)
    ..quadraticBezierTo(-25, -4, -24, -14)
    ..quadraticBezierTo(-22, -24, -8, -23)
    ..quadraticBezierTo(0, -21, 8, -23)
    ..quadraticBezierTo(22, -24, 24, -14)
    ..quadraticBezierTo(25, -4, 18, -4)
    ..lineTo(18, 20)
    ..close();
  c.drawPath(t, ink.lemon);
  c.drawPath(t, ink.line);
  final butter = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-6, -19, 13, 9),
    const Radius.circular(2),
  );
  c.drawRRect(butter, ink.lemon);
  c.drawRRect(butter, ink.line..strokeWidth = 1.3);
  ink.line.strokeWidth = 1.8;
  dotEyes(c, ink, y: 1, dx: 6.5, r: 1.5);
  smile(c, ink, y: 7, w: 5, depth: 2.6);
  blush(c, ink, dx: 11, y: 7);
}

/// A watermelon slice: seeds for eyes.
void watermelon(Canvas c, DoodleInk ink) {
  final slice = Path()
    ..moveTo(-26, -6)
    ..lineTo(26, -6)
    ..arcToPoint(
      const Offset(-26, -6),
      radius: const Radius.circular(26),
      clockwise: true,
    )
    ..close();
  c.drawPath(slice, ink.pink);
  c.drawPath(slice, ink.line);
  c.drawArc(
    Rect.fromCircle(center: const Offset(0, -6), radius: 21),
    0.15,
    math.pi - 0.3,
    false,
    ink.line..strokeWidth = 1.2,
  );
  ink.line.strokeWidth = 1.8;
  c.drawOval(
    Rect.fromCenter(center: const Offset(-7, 4), width: 3.4, height: 5.4),
    ink.dot,
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(7, 4), width: 3.4, height: 5.4),
    ink.dot,
  );
  smile(c, ink, y: 11, w: 5, depth: 2.4);
  for (final p in const [Offset(-15, 12), Offset(14, 13), Offset(0, 17)]) {
    c.drawOval(
      Rect.fromCenter(center: p, width: 2.6, height: 4),
      ink.line..strokeWidth = 1.2,
    );
  }
  ink.line.strokeWidth = 1.8;
}

/// An alarm clock that has had enough.
void alarmClock(Canvas c, DoodleInk ink) {
  c.drawCircle(const Offset(0, 3), 17, ink.bg);
  c.drawCircle(const Offset(0, 3), 17, ink.mint);
  c.drawCircle(const Offset(0, 3), 17, ink.line);
  c.drawArc(
    const Rect.fromLTWH(-20, -22, 14, 12),
    math.pi * 0.9,
    math.pi * 1.0,
    false,
    ink.line,
  );
  c.drawArc(
    const Rect.fromLTWH(6, -22, 14, 12),
    math.pi * 1.1,
    math.pi * 1.0,
    false,
    ink.line,
  );
  c.drawLine(const Offset(-10, 20), const Offset(-14, 26), ink.line);
  c.drawLine(const Offset(10, 20), const Offset(14, 26), ink.line);
  dotEyes(c, ink, y: 0, dx: 5.5, r: 1.5);
  c.drawPath(
    Path()
      ..moveTo(-5, 9)
      ..lineTo(-2.5, 6.5)
      ..lineTo(0, 9)
      ..lineTo(2.5, 6.5)
      ..lineTo(5, 9),
    ink.line,
  );
  c.drawLine(const Offset(0, -9), const Offset(0, -12), ink.line);
  for (final s in const [-1.0, 1.0]) {
    c.drawLine(Offset(s * 24, -8), Offset(s * 29, -10), ink.line);
    c.drawLine(Offset(s * 25, -2), Offset(s * 31, -2), ink.line);
  }
}

/// A snail, taking its time.
void snail(Canvas c, DoodleInk ink) {
  final body = Path()
    ..moveTo(-26, 16)
    ..lineTo(18, 16)
    ..quadraticBezierTo(26, 16, 25, 8)
    ..quadraticBezierTo(24, -2, 19, -6);
  c.drawPath(body, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-26, 16)
      ..quadraticBezierTo(-31, 10, -26, 6)
      ..quadraticBezierTo(-22, 8, -18, 10),
    ink.line,
  );
  c.drawCircle(const Offset(-6, 0), 15, ink.bg);
  c.drawCircle(const Offset(-6, 0), 15, ink.lemon);
  c.drawCircle(const Offset(-6, 0), 15, ink.line);
  c.drawPath(spiralPath(const Offset(-6, 0), 1, 11, 2.2), ink.line);
  // Eye stalks.
  c.drawLine(const Offset(19, -6), const Offset(17, -17), ink.line);
  c.drawLine(const Offset(23, -4), const Offset(25, -15), ink.line);
  c.drawCircle(const Offset(17, -19), 2.6, ink.bg);
  c.drawCircle(const Offset(17, -19), 2.6, ink.line);
  c.drawCircle(const Offset(25, -17), 2.6, ink.bg);
  c.drawCircle(const Offset(25, -17), 2.6, ink.line);
  c.drawCircle(const Offset(17.4, -19), 0.9, ink.dot);
  c.drawCircle(const Offset(25.4, -17), 0.9, ink.dot);
  c.drawPath(
    Path()
      ..moveTo(17, 3)
      ..quadraticBezierTo(20, 7, 23, 3),
    ink.line,
  );
}

/// A frog with a fly on its mind.
void frog(Canvas c, DoodleInk ink) {
  final head = Path()
    ..moveTo(-24, 10)
    ..quadraticBezierTo(-26, -6, -10, -8)
    ..quadraticBezierTo(0, -10, 10, -8)
    ..quadraticBezierTo(26, -6, 24, 10)
    ..quadraticBezierTo(22, 22, 0, 22)
    ..quadraticBezierTo(-22, 22, -24, 10);
  c.drawPath(head, ink.mint);
  c.drawPath(head, ink.line);
  for (final x in const [-12.0, 12.0]) {
    c.drawCircle(Offset(x, -10), 7, ink.bg);
    c.drawCircle(Offset(x, -10), 7, ink.mint);
    c.drawCircle(Offset(x, -10), 7, ink.line);
    c.drawCircle(Offset(x + (x < 0 ? 1.5 : -1.5), -9), 2.4, ink.dot);
  }
  c.drawPath(
    Path()
      ..moveTo(-15, 8)
      ..quadraticBezierTo(0, 22, 15, 8),
    ink.line,
  );
  c.drawCircle(const Offset(-3, 4), 0.9, ink.dot);
  c.drawCircle(const Offset(3, 4), 0.9, ink.dot);
  // The fly.
  c.drawCircle(const Offset(28, -20), 1.8, ink.dot);
  c.drawOval(
    Rect.fromCenter(center: const Offset(24, -23), width: 6, height: 3.5),
    ink.line..strokeWidth = 1.2,
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(32, -23), width: 6, height: 3.5),
    ink.line,
  );
  ink.line.strokeWidth = 1.8;
}

/// An avocado half, the pit wearing a face.
void avocado(Canvas c, DoodleInk ink) {
  final a = Path()
    ..moveTo(0, -24)
    ..cubicTo(-10, -24, -12, -10, -17, -2)
    ..cubicTo(-26, 12, -14, 25, 0, 25)
    ..cubicTo(14, 25, 26, 12, 17, -2)
    ..cubicTo(12, -10, 10, -24, 0, -24);
  c.drawPath(a, ink.mint);
  c.drawPath(a, ink.line);
  final inner = Path()
    ..moveTo(0, -18)
    ..cubicTo(-7, -18, -9, -8, -13, -1)
    ..cubicTo(-20, 11, -10, 20, 0, 20)
    ..cubicTo(10, 20, 20, 11, 13, -1)
    ..cubicTo(9, -8, 7, -18, 0, -18);
  c.drawPath(inner, ink.line..strokeWidth = 1.2);
  ink.line.strokeWidth = 1.8;
  c.drawCircle(const Offset(0, 8), 9, ink.lemon);
  c.drawCircle(const Offset(0, 8), 9, ink.line);
  dotEyes(c, ink, y: 6, dx: 3.2, r: 1.2);
  smile(c, ink, y: 10, w: 3, depth: 1.6);
}

// ------------------------------------------------------------ just things ---

/// A rocket with a flame, going somewhere.
void rocket(Canvas c, DoodleInk ink) {
  c.save();
  c.rotate(0.6);
  final body = Path()
    ..moveTo(0, -26)
    ..quadraticBezierTo(14, -12, 10, 12)
    ..lineTo(-10, 12)
    ..quadraticBezierTo(-14, -12, 0, -26);
  c.drawPath(body, ink.bg);
  c.drawPath(body, ink.mint);
  c.drawPath(body, ink.line);
  c.drawCircle(const Offset(0, -6), 4.5, ink.bg);
  c.drawCircle(const Offset(0, -6), 4.5, ink.line);
  c.drawPath(
    polyPath(const [
      Offset(-10, 4),
      Offset(-18, 16),
      Offset(-10, 12),
    ], close: false),
    ink.line,
  );
  c.drawPath(
    polyPath(const [
      Offset(10, 4),
      Offset(18, 16),
      Offset(10, 12),
    ], close: false),
    ink.line,
  );
  final flame = Path()
    ..moveTo(-6, 12)
    ..quadraticBezierTo(0, 32, 6, 12);
  c.drawPath(flame, ink.lemon);
  c.drawPath(flame, ink.line);
  c.restore();
  c.drawLine(const Offset(-26, 18), const Offset(-18, 14), ink.line);
  c.drawLine(const Offset(-22, 26), const Offset(-14, 20), ink.line);
}

/// An open umbrella in the rain.
void umbrella(Canvas c, DoodleInk ink) {
  final top = Path()
    ..moveTo(-26, 2)
    ..quadraticBezierTo(-26, -22, 0, -22)
    ..quadraticBezierTo(26, -22, 26, 2)
    ..quadraticBezierTo(20, -3, 13, 2)
    ..quadraticBezierTo(6.5, -3, 0, 2)
    ..quadraticBezierTo(-6.5, -3, -13, 2)
    ..quadraticBezierTo(-20, -3, -26, 2);
  c.drawPath(top, ink.pink);
  c.drawPath(top, ink.line);
  c.drawLine(
    const Offset(0, -22),
    const Offset(0, 2),
    ink.line..strokeWidth = 1.1,
  );
  c.drawPath(
    Path()
      ..moveTo(-13, 2)
      ..quadraticBezierTo(-10, -12, 0, -22),
    ink.line,
  );
  c.drawPath(
    Path()
      ..moveTo(13, 2)
      ..quadraticBezierTo(10, -12, 0, -22),
    ink.line,
  );
  ink.line.strokeWidth = 1.8;
  c.drawPath(
    Path()
      ..moveTo(0, 2)
      ..lineTo(0, 22)
      ..quadraticBezierTo(0, 28, -6, 26),
    ink.line,
  );
  for (final p in const [
    Offset(-22, 12),
    Offset(22, 8),
    Offset(-12, 18),
    Offset(13, 17),
  ]) {
    c.drawPath(teardropPath(p, 5, 1.4), ink.line);
  }
}

/// A key on a ring.
void keyDoodle(Canvas c, DoodleInk ink) {
  c.save();
  c.rotate(-0.7);
  c.drawCircle(const Offset(-14, 0), 9, ink.lemon);
  c.drawCircle(const Offset(-14, 0), 9, ink.line);
  c.drawCircle(const Offset(-14, 0), 3.4, ink.line);
  c.drawLine(const Offset(-5, 0), const Offset(22, 0), ink.line);
  c.drawPath(
    polyPath(const [
      Offset(14, 0),
      Offset(14, 7),
      Offset(18, 7),
      Offset(18, 0),
    ], close: false),
    ink.line,
  );
  c.drawPath(
    polyPath(const [Offset(21, 0), Offset(21, 5)], close: false),
    ink.line,
  );
  c.restore();
}

/// A swirly lollipop.
void lollipop(Canvas c, DoodleInk ink) {
  c.drawLine(const Offset(0, 6), const Offset(0, 28), ink.line);
  c.drawCircle(const Offset(0, -10), 16, ink.pink);
  c.drawCircle(const Offset(0, -10), 16, ink.line);
  c.drawPath(spiralPath(const Offset(0, -10), 1.5, 12, 2.6), ink.line);
  c.drawPath(
    polyPath(const [
      Offset(-3, 18),
      Offset(3, 14),
      Offset(3, 22),
      Offset(-3, 18),
    ], close: false),
    ink.line..strokeWidth = 1.3,
  );
  ink.line.strokeWidth = 1.8;
}

/// A folded paper plane with a dotted flight path.
void paperPlane(Canvas c, DoodleInk ink) {
  final plane = polyPath(const [
    Offset(-24, 2),
    Offset(26, -14),
    Offset(6, 18),
  ]);
  c.drawPath(plane, ink.mint);
  c.drawPath(plane, ink.line);
  c.drawPath(
    polyPath(const [
      Offset(-24, 2),
      Offset(26, -14),
      Offset(-2, 6),
      Offset(0, 14),
      Offset(6, 18),
    ], close: false),
    ink.line..strokeWidth = 1.2,
  );
  ink.line.strokeWidth = 1.8;
  for (final p in const [Offset(-26, 14), Offset(-20, 18), Offset(-12, 20)]) {
    c.drawCircle(p, 1.1, ink.dot);
  }
}

/// A little potted plant.
void pottedPlant(Canvas c, DoodleInk ink) {
  final pot = polyPath(const [
    Offset(-12, 8),
    Offset(12, 8),
    Offset(9, 24),
    Offset(-9, 24),
  ]);
  c.drawPath(pot, ink.lemon);
  c.drawPath(pot, ink.line);
  c.drawLine(
    const Offset(-14, 8),
    const Offset(14, 8),
    ink.line..strokeWidth = 2.6,
  );
  ink.line.strokeWidth = 1.8;
  c.drawLine(const Offset(0, 8), const Offset(0, -10), ink.line);
  for (final l in const [
    [-1.0, -4.0],
    [1.0, -10.0],
    [-1.0, -16.0],
  ]) {
    final s = l[0], y = l[1];
    final leaf = Path()
      ..moveTo(0, y + 6)
      ..quadraticBezierTo(s * 14, y + 2, s * 15, y - 5)
      ..quadraticBezierTo(s * 3, y - 3, 0, y + 6);
    c.drawPath(leaf, ink.mint);
    c.drawPath(leaf, ink.line);
  }
}

/// Headphones, volume up.
void headphones(Canvas c, DoodleInk ink) {
  c.drawArc(
    const Rect.fromLTWH(-20, -22, 40, 40),
    math.pi,
    math.pi,
    false,
    ink.line,
  );
  for (final s in const [-1.0, 1.0]) {
    final cup = RRect.fromRectAndRadius(
      Rect.fromLTWH(s < 0 ? -25 : 13, -4, 12, 22),
      const Radius.circular(5),
    );
    c.drawRRect(cup, ink.bg);
    c.drawRRect(cup, ink.pink);
    c.drawRRect(cup, ink.line);
  }
  c.drawPath(
    Path()
      ..moveTo(-30, 0)
      ..quadraticBezierTo(-33, 7, -30, 14),
    ink.line..strokeWidth = 1.4,
  );
  c.drawPath(
    Path()
      ..moveTo(30, 0)
      ..quadraticBezierTo(33, 7, 30, 14),
    ink.line,
  );
  ink.line.strokeWidth = 1.8;
  c.drawPath(
    Path()
      ..moveTo(-12, 22)
      ..quadraticBezierTo(-4, 28, 4, 24),
    ink.line,
  );
  c.drawPath(
    polyPath(const [
      Offset(-3, -6),
      Offset(2, -12),
      Offset(5, -4),
      Offset(10, -10),
    ], close: false),
    ink.line..strokeWidth = 1.4,
  );
  ink.line.strokeWidth = 1.8;
}

/// A retro camera.
void camera(Canvas c, DoodleInk ink) {
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-24, -10, 48, 30),
    const Radius.circular(5),
  );
  c.drawRRect(body, ink.bg);
  c.drawRRect(body, ink.mint);
  c.drawRRect(body, ink.line);
  c.drawPath(
    polyPath(const [
      Offset(-10, -10),
      Offset(-7, -17),
      Offset(7, -17),
      Offset(10, -10),
    ], close: false),
    ink.line,
  );
  c.drawCircle(const Offset(0, 5), 10, ink.bg);
  c.drawCircle(const Offset(0, 5), 10, ink.line);
  c.drawCircle(const Offset(0, 5), 5, ink.line);
  c.drawCircle(const Offset(-2, 3), 1.2, ink.dot);
  c.drawCircle(const Offset(17, -4), 2.2, ink.line);
  c.drawLine(const Offset(-19, -4), const Offset(-12, -4), ink.line);
}

/// A sneaker with a lace.
void sneaker(Canvas c, DoodleInk ink) {
  final shoe = Path()
    ..moveTo(-24, 14)
    ..lineTo(-24, -6)
    ..quadraticBezierTo(-24, -12, -18, -12)
    ..lineTo(-8, -12)
    ..quadraticBezierTo(-4, -2, 6, 0)
    ..quadraticBezierTo(24, 2, 26, 10)
    ..lineTo(26, 14)
    ..close();
  c.drawPath(shoe, ink.pink);
  c.drawPath(shoe, ink.line);
  c.drawLine(
    const Offset(-26, 19),
    const Offset(28, 19),
    ink.line..strokeWidth = 3.2,
  );
  ink.line.strokeWidth = 1.8;
  for (final p in const [Offset(-4, -3), Offset(1, 0), Offset(7, 2)]) {
    c.drawLine(p, p + const Offset(5, -4), ink.line..strokeWidth = 1.4);
  }
  ink.line.strokeWidth = 1.8;
  c.drawPath(
    Path()
      ..moveTo(-24, 6)
      ..quadraticBezierTo(-10, 10, -4, 14),
    ink.line,
  );
}

/// A daisy.
void daisy(Canvas c, DoodleInk ink) {
  for (var i = 0; i < 8; i++) {
    final a = i / 8 * 2 * math.pi;
    c.save();
    c.rotate(a);
    c.drawOval(const Rect.fromLTWH(-4, -22, 8, 13), ink.bg);
    c.drawOval(const Rect.fromLTWH(-4, -22, 8, 13), ink.line);
    c.restore();
  }
  c.drawCircle(Offset.zero, 6.5, ink.lemon);
  c.drawCircle(Offset.zero, 6.5, ink.line);
}

/// A fish with a bubble.
void fish(Canvas c, DoodleInk ink) {
  final body = Path()
    ..moveTo(-24, 0)
    ..quadraticBezierTo(-6, -20, 14, 0)
    ..quadraticBezierTo(-6, 20, -24, 0);
  c.drawPath(body, ink.mint);
  c.drawPath(body, ink.line);
  c.drawPath(
    polyPath(const [
      Offset(13, 0),
      Offset(26, -10),
      Offset(23, 0),
      Offset(26, 10),
    ]),
    ink.line,
  );
  c.drawCircle(const Offset(-14, -3), 1.6, ink.dot);
  c.drawPath(
    Path()
      ..moveTo(-8, -6)
      ..quadraticBezierTo(-4, 0, -8, 6),
    ink.line..strokeWidth = 1.2,
  );
  ink.line.strokeWidth = 1.8;
  c.drawCircle(const Offset(-30, -12), 2.4, ink.line);
  c.drawCircle(const Offset(-34, -20), 1.6, ink.line);
}

/// A crown.
void crown(Canvas c, DoodleInk ink) {
  final p = polyPath(const [
    Offset(-22, 14),
    Offset(-26, -12),
    Offset(-11, 0),
    Offset(0, -18),
    Offset(11, 0),
    Offset(26, -12),
    Offset(22, 14),
  ]);
  c.drawPath(p, ink.lemon);
  c.drawPath(p, ink.line);
  c.drawLine(
    const Offset(-22, 8),
    const Offset(22, 8),
    ink.line..strokeWidth = 1.3,
  );
  ink.line.strokeWidth = 1.8;
  for (final x in const [-12.0, 0.0, 12.0]) {
    c.drawCircle(Offset(x, 11), 1.4, ink.dot);
  }
  for (final o in const [Offset(-26, -15), Offset(0, -21), Offset(26, -15)]) {
    c.drawCircle(o, 2.4, ink.pink);
    c.drawCircle(o, 2.4, ink.line);
  }
}

/// Two cherries.
void cherries(Canvas c, DoodleInk ink) {
  c.drawPath(
    Path()
      ..moveTo(-8, 10)
      ..quadraticBezierTo(-8, -10, 8, -22),
    ink.line,
  );
  c.drawPath(
    Path()
      ..moveTo(10, 12)
      ..quadraticBezierTo(10, -8, 8, -22),
    ink.line,
  );
  final leaf = Path()
    ..moveTo(8, -22)
    ..quadraticBezierTo(18, -28, 25, -19)
    ..quadraticBezierTo(15, -14, 8, -22);
  c.drawPath(leaf, ink.mint);
  c.drawPath(leaf, ink.line);
  for (final p in const [Offset(-9, 14), Offset(11, 16)]) {
    c.drawCircle(p, 8.5, ink.bg);
    c.drawCircle(p, 8.5, ink.pink);
    c.drawCircle(p, 8.5, ink.line);
    c.drawArc(
      Rect.fromCircle(center: p, radius: 4.8),
      math.pi * 1.05,
      math.pi * 0.5,
      false,
      ink.line..strokeWidth = 1.2,
    );
  }
  ink.line.strokeWidth = 1.8;
}

/// An envelope with a heart seal: a love letter.
void loveLetter(Canvas c, DoodleInk ink) {
  final env = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-24, -15, 48, 32),
    const Radius.circular(4),
  );
  c.drawRRect(env, ink.bg);
  c.drawRRect(env, ink.lemon);
  c.drawRRect(env, ink.line);
  c.drawPath(
    polyPath(const [
      Offset(-24, -13),
      Offset(0, 5),
      Offset(24, -13),
    ], close: false),
    ink.line,
  );
  c.drawPath(
    polyPath(const [Offset(-24, 15), Offset(-8, 0)], close: false),
    ink.line,
  );
  c.drawPath(
    polyPath(const [Offset(24, 15), Offset(8, 0)], close: false),
    ink.line,
  );
  final heart = Path()
    ..moveTo(0, 12)
    ..cubicTo(-12, 3, -6, -6, 0, -1)
    ..cubicTo(6, -6, 12, 3, 0, 12);
  c.save();
  c.translate(0, 0);
  c.drawPath(heart, ink.bg);
  c.drawPath(heart, ink.pink);
  c.drawPath(heart, ink.line);
  c.restore();
}

/// A speech bubble that is typing...
void typingBubble(Canvas c, DoodleInk ink) {
  final b = Path()
    ..moveTo(-22, -14)
    ..lineTo(22, -14)
    ..quadraticBezierTo(26, -14, 26, -10)
    ..lineTo(26, 6)
    ..quadraticBezierTo(26, 10, 22, 10)
    ..lineTo(-6, 10)
    ..lineTo(-16, 20)
    ..lineTo(-14, 10)
    ..lineTo(-22, 10)
    ..quadraticBezierTo(-26, 10, -26, 6)
    ..lineTo(-26, -10)
    ..quadraticBezierTo(-26, -14, -22, -14);
  c.drawPath(b, ink.mint);
  c.drawPath(b, ink.line);
  for (final x in const [-11.0, 0.0, 11.0]) {
    c.drawCircle(Offset(x, -2), 2.3, ink.dot);
  }
}

/// A speech bubble that cannot believe it.
void shockBubble(Canvas c, DoodleInk ink) {
  final b = Path()
    ..moveTo(-18, -18)
    ..quadraticBezierTo(-26, -18, -26, -10)
    ..lineTo(-26, 4)
    ..quadraticBezierTo(-26, 12, -18, 12)
    ..lineTo(-14, 12)
    ..lineTo(-18, 22)
    ..lineTo(-6, 12)
    ..lineTo(18, 12)
    ..quadraticBezierTo(26, 12, 26, 4)
    ..lineTo(26, -10)
    ..quadraticBezierTo(26, -18, 18, -18)
    ..close();
  c.drawPath(b, ink.pink);
  c.drawPath(b, ink.line);
  c.drawLine(
    const Offset(-6, -11),
    const Offset(-6, 0),
    ink.line..strokeWidth = 2.6,
  );
  c.drawCircle(const Offset(-6, 5), 1.5, ink.dot);
  c.drawPath(
    Path()
      ..moveTo(5, -8)
      ..quadraticBezierTo(5, -13, 10, -12)
      ..quadraticBezierTo(15, -11, 12, -6)
      ..quadraticBezierTo(10, -3, 10, 0),
    ink.line..strokeWidth = 2.2,
  );
  c.drawCircle(const Offset(10, 5), 1.5, ink.dot);
  ink.line.strokeWidth = 1.8;
}

/// A pencil, mid-doodle.
void pencil(Canvas c, DoodleInk ink) {
  c.save();
  c.rotate(-0.75);
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-22, -5, 36, 10),
    const Radius.circular(1),
  );
  c.drawRRect(body, ink.lemon);
  c.drawRRect(body, ink.line);
  c.drawPath(
    polyPath(const [Offset(14, -5), Offset(24, 0), Offset(14, 5)]),
    ink.line,
  );
  c.drawLine(const Offset(19, -2.4), const Offset(19, 2.4), ink.line);
  final eraser = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-28, -5, 6, 10),
    const Radius.circular(2),
  );
  c.drawRRect(eraser, ink.pink);
  c.drawRRect(eraser, ink.line);
  c.drawLine(
    const Offset(-14, -5),
    const Offset(-14, 5),
    ink.line..strokeWidth = 1.1,
  );
  ink.line.strokeWidth = 1.8;
  c.restore();
  c.drawPath(wavePath(const Offset(-6, 25), 30, 3, 3), ink.line);
}

/// An ice pop with a bite taken out.
void icePop(Canvas c, DoodleInk ink) {
  c.drawLine(
    const Offset(0, 14),
    const Offset(0, 28),
    ink.line..strokeWidth = 5,
  );
  c.drawLine(
    const Offset(0, 14),
    const Offset(0, 28),
    ink.bgStroke..strokeWidth = 2,
  );
  ink.line.strokeWidth = 1.8;
  final pop = Path()
    ..moveTo(-12, 14)
    ..lineTo(-12, -10)
    ..quadraticBezierTo(-12, -24, 0, -24)
    ..quadraticBezierTo(8, -24, 11, -18)
    ..quadraticBezierTo(6, -16, 7, -12)
    ..quadraticBezierTo(13, -10, 12, -4)
    ..lineTo(12, 14)
    ..close();
  c.drawPath(pop, ink.mint);
  c.drawPath(pop, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-12, 0)
      ..lineTo(12, 0),
    ink.line..strokeWidth = 1.1,
  );
  ink.line.strokeWidth = 1.8;
  c.drawArc(
    const Rect.fromLTWH(-8, -20, 8, 10),
    math.pi * 1.1,
    math.pi * 0.6,
    false,
    ink.line,
  );
  c.drawCircle(const Offset(20, -16), 1.2, ink.dot);
  c.drawCircle(const Offset(17, -23), 1.0, ink.dot);
}

// ----------------------------------------------------------------- fillers ---

void sparkleFiller(Canvas c, DoodleInk ink) =>
    sparkleAt(c, ink, Offset.zero, 8);

void heartFiller(Canvas c, DoodleInk ink) {
  final p = Path()
    ..moveTo(0, 8)
    ..cubicTo(-15, -2, -8, -13, 0, -5)
    ..cubicTo(8, -13, 15, -2, 0, 8);
  c.drawPath(p, ink.pink);
  c.drawPath(p, ink.line);
}

void starFiller(Canvas c, DoodleInk ink) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? 9.0 : 4.2;
    final a = -math.pi / 2 + i * math.pi / 5;
    final o = Offset(r * math.cos(a), r * math.sin(a));
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  c.drawPath(p..close(), ink.line);
}

void squiggleFiller(Canvas c, DoodleInk ink) =>
    c.drawPath(wavePath(const Offset(-14, 0), 28, 3.4, 3), ink.line);

void zigzagFiller(Canvas c, DoodleInk ink) => c.drawPath(
  polyPath(const [
    Offset(-12, 3),
    Offset(-6, -3),
    Offset(0, 3),
    Offset(6, -3),
    Offset(12, 3),
  ], close: false),
  ink.line,
);

void boltFiller(Canvas c, DoodleInk ink) => c.drawPath(
  polyPath(const [
    Offset(3, -10),
    Offset(-5, 2),
    Offset(0, 2),
    Offset(-3, 10),
    Offset(6, -2),
    Offset(1, -2),
  ]),
  ink.line,
);

void dotsFiller(Canvas c, DoodleInk ink) {
  for (final o in const [Offset(-7, 2), Offset(0, -2.5), Offset(7, 2)]) {
    c.drawCircle(o, 1.6, ink.dot);
  }
}

void ringFiller(Canvas c, DoodleInk ink) =>
    c.drawCircle(Offset.zero, 4.6, ink.line);

void plusFiller(Canvas c, DoodleInk ink) {
  c.drawLine(const Offset(-4.5, 0), const Offset(4.5, 0), ink.line);
  c.drawLine(const Offset(0, -4.5), const Offset(0, 4.5), ink.line);
}

void swirlFiller(Canvas c, DoodleInk ink) =>
    c.drawPath(spiralPath(Offset.zero, 1, 8, 1.6), ink.line);

void musicNote(Canvas c, DoodleInk ink) {
  c.drawOval(
    Rect.fromCenter(center: const Offset(-3, 7), width: 8, height: 6),
    ink.dot,
  );
  c.drawLine(const Offset(0.5, 6), const Offset(0.5, -9), ink.line);
  c.drawPath(
    Path()
      ..moveTo(0.5, -9)
      ..quadraticBezierTo(8, -7, 6, 0),
    ink.line,
  );
}

void crossX(Canvas c, DoodleInk ink) {
  c.drawLine(const Offset(-4, -4), const Offset(4, 4), ink.line);
  c.drawLine(const Offset(4, -4), const Offset(-4, 4), ink.line);
}

void tinyCrescent(Canvas c, DoodleInk ink) {
  final moon = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 8)),
    Path()..addOval(Rect.fromCircle(center: const Offset(4, -2), radius: 7)),
  );
  c.drawPath(moon, ink.line);
}

void tinyFlower(Canvas c, DoodleInk ink) {
  for (var i = 0; i < 5; i++) {
    final a = i / 5 * 2 * math.pi;
    c.drawCircle(
      Offset(4.6 * math.cos(a), 4.6 * math.sin(a)),
      2.8,
      ink.line..strokeWidth = 1.3,
    );
  }
  ink.line.strokeWidth = 1.8;
  c.drawCircle(Offset.zero, 2, ink.lemon);
}

void leaf(Canvas c, DoodleInk ink) {
  final p = Path()
    ..moveTo(-9, 6)
    ..quadraticBezierTo(-10, -8, 8, -9)
    ..quadraticBezierTo(8, 6, -9, 6);
  c.drawPath(p, ink.mint);
  c.drawPath(p, ink.line);
  c.drawLine(
    const Offset(-9, 6),
    const Offset(3, -4),
    ink.line..strokeWidth = 1.1,
  );
  ink.line.strokeWidth = 1.8;
}

void triangleOutline(Canvas c, DoodleInk ink) => c.drawPath(
  polyPath(const [Offset(0, -7), Offset(7, 5), Offset(-7, 5)]),
  ink.line,
);

void asterisk(Canvas c, DoodleInk ink) {
  for (var i = 0; i < 3; i++) {
    final a = i * math.pi / 3;
    c.drawLine(
      Offset(-5 * math.cos(a), -5 * math.sin(a)),
      Offset(5 * math.cos(a), 5 * math.sin(a)),
      ink.line,
    );
  }
}

void tinyCloud(Canvas c, DoodleInk ink) {
  final p = Path()
    ..moveTo(-9, 4)
    ..quadraticBezierTo(-13, 4, -12, 0)
    ..quadraticBezierTo(-11, -4, -7, -3)
    ..quadraticBezierTo(-6, -9, 0, -8)
    ..quadraticBezierTo(5, -9, 6, -4)
    ..quadraticBezierTo(12, -4, 11, 1)
    ..quadraticBezierTo(11, 4, 8, 4)
    ..close();
  c.drawPath(p, ink.line);
}
