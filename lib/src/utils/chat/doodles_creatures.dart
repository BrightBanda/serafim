import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/doodle_kit.dart';

// ---------------------------------------------------------------- doodles ---

/// Mismatched eyes, one eyebrow up, a lopsided grin and the tongue out.
void goofyFace(Canvas c, DoodleInk ink) {
  c.drawCircle(Offset.zero, 22, ink.line);
  eyeAt(
    c,
    ink,
    const Offset(-8, -5),
    6.5,
    const Offset(2, 1.5),
    2.4,
  ); // big eye
  eyeAt(
    c,
    ink,
    const Offset(10, -4),
    3.2,
    const Offset(-0.6, 0.4),
    1.4,
  ); // tiny eye
  c.drawArc(
    const Rect.fromLTWH(-15, -21, 12, 8),
    math.pi * 1.05,
    math.pi * 0.9,
    false,
    ink.line,
  ); // raised brow
  c.drawLine(
    const Offset(5, -12),
    const Offset(15, -14.5),
    ink.line,
  ); // flat brow
  // Lopsided open grin with a tongue hanging out.
  final mouth = Path()
    ..moveTo(-13, 5)
    ..quadraticBezierTo(0, 20, 14, 3);
  final tongue = Path()
    ..moveTo(2, 11.5)
    ..lineTo(2, 18)
    ..quadraticBezierTo(6.5, 24, 11, 17.5)
    ..lineTo(10.2, 8.6);
  c.drawPath(tongue, ink.pink);
  c.drawPath(tongue, ink.line);
  c.drawLine(const Offset(6.5, 12.5), const Offset(6.5, 18), ink.line);
  c.drawPath(mouth, ink.line);
  c.drawCircle(const Offset(-15, 6), 2.2, ink.pink); // blush
}

/// A cone, a scoop mid-fall and the splat waiting underneath.
void iceCreamSpill(Canvas c, DoodleInk ink) {
  c.save();
  c.translate(-8, 0);
  c.rotate(-0.22);
  // Cone with waffle crosshatch.
  final cone = polyPath(const [Offset(-12, -4), Offset(12, -4), Offset(0, 30)]);
  c.drawPath(cone, ink.lemon);
  c.save();
  c.clipPath(cone);
  for (var i = -3; i < 6; i++) {
    c.drawLine(
      Offset(-16.0 + i * 6, -4),
      Offset(-16.0 + i * 6 + 18, 30),
      ink.line..strokeWidth = 1.0,
    );
    c.drawLine(
      Offset(16.0 - i * 6, -4),
      Offset(16.0 - i * 6 - 18, 30),
      ink.line,
    );
  }
  c.restore();
  ink.line.strokeWidth = 1.8;
  c.drawPath(cone, ink.line);
  // What is left on the cone: a dripping half scoop.
  final stub = Path()
    ..moveTo(-15, -3)
    ..quadraticBezierTo(-17, -17, -2, -17)
    ..quadraticBezierTo(14, -17, 15, -3)
    ..quadraticBezierTo(11, 3, 8, -3)
    ..quadraticBezierTo(4, 6, 0, -3)
    ..quadraticBezierTo(-4, 1, -8, -3)
    ..quadraticBezierTo(-11, 2, -15, -3);
  c.drawPath(stub, ink.pink);
  c.drawPath(stub, ink.line);
  c.restore();
  // The scoop that did not make it.
  const scoop = Offset(20, 0);
  c.drawCircle(scoop, 9, ink.pink);
  c.drawCircle(scoop, 9, ink.line);
  c.drawArc(
    Rect.fromCircle(center: scoop, radius: 5),
    math.pi * 1.1,
    math.pi * 0.5,
    false,
    ink.line,
  );
  c.drawLine(const Offset(16, -13), const Offset(16, -20), ink.line);
  c.drawLine(const Offset(22, -14), const Offset(22, -23), ink.line);
  // And the splat it is heading for.
  final splat = Path()
    ..moveTo(6, 27)
    ..quadraticBezierTo(10, 22, 15, 26)
    ..quadraticBezierTo(20, 21, 25, 26)
    ..quadraticBezierTo(33, 24, 31, 30)
    ..quadraticBezierTo(20, 34, 6, 32)
    ..quadraticBezierTo(2, 29.5, 6, 27);
  c.drawPath(splat, ink.pink);
  c.drawPath(splat, ink.line);
  c.drawCircle(const Offset(35, 20), 1.4, ink.dot);
  c.drawCircle(const Offset(2, 23), 1.2, ink.dot);
}

/// Spiral eyes, a wobbly mouth, and stars circling the head.
void dizzyFace(Canvas c, DoodleInk ink) {
  c.drawCircle(const Offset(0, 4), 20, ink.line);
  c.drawPath(spiralPath(const Offset(-8, 0), 0.6, 6.5, 2.2), ink.line);
  c.drawPath(spiralPath(const Offset(9, 1), 0.6, 6.5, 2.2, start: 2), ink.line);
  c.drawPath(wavePath(const Offset(-9, 14), 18, 2.6, 3), ink.line);
  for (final s in const [Offset(-14, -23), Offset(2, -27), Offset(17, -22)]) {
    sparkleAt(c, ink, s, 4.2);
  }
}

/// Wide eyes, a huge "AAAH" mouth, sweat flying off.
void screamFace(Canvas c, DoodleInk ink) {
  c.drawOval(const Rect.fromLTWH(-19, -24, 38, 46), ink.line);
  c.drawCircle(const Offset(-7, -8), 5.5, ink.line);
  c.drawCircle(const Offset(7, -8), 5.5, ink.line);
  c.drawCircle(const Offset(-7, -8), 1.6, ink.dot);
  c.drawCircle(const Offset(7, -8), 1.6, ink.dot);
  c.drawLine(const Offset(-13, -18), const Offset(-4, -15), ink.line);
  c.drawLine(const Offset(13, -18), const Offset(4, -15), ink.line);
  final mouth = Rect.fromCenter(
    center: const Offset(0, 9),
    width: 14,
    height: 16,
  );
  c.drawOval(mouth, ink.mint);
  c.drawOval(mouth, ink.line);
  c.drawPath(teardropPath(const Offset(-26, -16), 8, 3), ink.line);
  c.drawPath(teardropPath(const Offset(27, -10), 8, 3), ink.line);
  c.drawLine(const Offset(-6, -29), const Offset(-8, -34), ink.line);
  c.drawLine(const Offset(0, -30), const Offset(0, -36), ink.line);
  c.drawLine(const Offset(6, -29), const Offset(8, -34), ink.line);
}

/// A frosted donut with sprinkles.
void donut(Canvas c, DoodleInk ink) {
  c.drawCircle(Offset.zero, 21, ink.line);
  // Smooth, wobbly icing with the hole cut out of it.
  final wavy = Path();
  const steps = 72;
  for (var i = 0; i <= steps; i++) {
    final a = i / steps * 2 * math.pi;
    final r = 16.5 + 2.3 * math.sin(a * 7);
    final p = Offset(r * math.cos(a), r * math.sin(a));
    i == 0 ? wavy.moveTo(p.dx, p.dy) : wavy.lineTo(p.dx, p.dy);
  }
  wavy.close();
  final hole = Path()
    ..addOval(Rect.fromCircle(center: Offset.zero, radius: 6.5));
  c.drawPath(Path.combine(PathOperation.difference, wavy, hole), ink.pink);
  c.drawPath(wavy, ink.line..strokeWidth = 1.4);
  ink.line.strokeWidth = 1.8;
  c.drawPath(hole, ink.line);
  for (final s in const [
    [Offset(-10, -8), 0.6],
    [Offset(8, -11), -0.8],
    [Offset(12, 3), 1.2],
    [Offset(-4, 12), -0.3],
    [Offset(-13, 3), 0.9],
    [Offset(4, 9), 0.2],
  ]) {
    final o = s[0] as Offset;
    final a = s[1] as double;
    c.drawLine(
      o,
      o + Offset(3 * math.cos(a), 3 * math.sin(a)),
      ink.line..strokeWidth = 1.7,
    );
  }
  ink.line.strokeWidth = 1.8;
}

/// A cat who has just seen something silly: squinting, tongue out.
void sillyCat(Canvas c, DoodleInk ink) {
  final head = Path()
    ..moveTo(-20, 4)
    ..lineTo(-21, -18)
    ..lineTo(-8, -10)
    ..quadraticBezierTo(0, -13, 8, -10)
    ..lineTo(21, -18)
    ..lineTo(20, 4)
    ..quadraticBezierTo(18, 22, 0, 22)
    ..quadraticBezierTo(-18, 22, -20, 4);
  c.drawPath(head, ink.line);
  c.drawPath(
    polyPath(const [
      Offset(-17, -13),
      Offset(-12, -9),
      Offset(-17, -6),
    ], close: false),
    ink.line,
  );
  c.drawPath(
    polyPath(const [
      Offset(-12, -2),
      Offset(-6, 1),
      Offset(-12, 3),
    ], close: false),
    ink.line,
  ); // > eye
  c.drawPath(
    polyPath(const [Offset(12, -2), Offset(6, 1), Offset(12, 3)], close: false),
    ink.line,
  ); // < eye
  c.drawPath(
    polyPath(const [Offset(-2.5, 7), Offset(2.5, 7), Offset(0, 10)]),
    ink.pink,
  );
  c.drawPath(
    polyPath(const [Offset(-2.5, 7), Offset(2.5, 7), Offset(0, 10)]),
    ink.line,
  );
  final tongue = Path()
    ..moveTo(-1.5, 13.5)
    ..lineTo(-1.5, 17.5)
    ..quadraticBezierTo(1.5, 21, 4.5, 17.5)
    ..lineTo(4.5, 13);
  c.drawPath(tongue, ink.pink);
  c.drawPath(tongue, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-9, 11)
      ..quadraticBezierTo(-4, 15, 0, 10)
      ..quadraticBezierTo(4, 15, 9, 11),
    ink.line,
  );
  for (final y in const [4.0, 8.0]) {
    c.drawLine(Offset(-25, y - 2), Offset(-16, y), ink.line);
    c.drawLine(Offset(25, y - 2), Offset(16, y), ink.line);
  }
}

/// A ghost who is bad at haunting.
void goofyGhost(Canvas c, DoodleInk ink) {
  final body = Path()
    ..moveTo(-16, 22)
    ..lineTo(-16, -6)
    ..quadraticBezierTo(-16, -24, 0, -24)
    ..quadraticBezierTo(16, -24, 16, -6)
    ..lineTo(16, 22)
    ..quadraticBezierTo(11, 16, 8, 22)
    ..quadraticBezierTo(4, 28, 0, 22)
    ..quadraticBezierTo(-4, 16, -8, 22)
    ..quadraticBezierTo(-12, 28, -16, 22);
  c.drawPath(body, ink.line);
  c.drawCircle(const Offset(-6, -8), 3.2, ink.line);
  c.drawCircle(const Offset(7, -9), 2.2, ink.line);
  c.drawCircle(const Offset(-5, -7), 1.2, ink.dot);
  c.drawCircle(const Offset(7, -8.5), 1.0, ink.dot);
  c.drawOval(
    Rect.fromCenter(center: const Offset(1, 5), width: 7, height: 9),
    ink.line,
  );
  c.drawPath(
    Path()
      ..moveTo(16, -2)
      ..quadraticBezierTo(26, -10, 22, -20),
    ink.line,
  );
  c.drawLine(const Offset(-24, -14), const Offset(-20, -17), ink.line);
  c.drawLine(const Offset(-26, -8), const Offset(-21, -9), ink.line);
}

/// A rubber duck, mid-quack.
void rubberDuck(Canvas c, DoodleInk ink) {
  // Body with a perky tail.
  final body = Path()
    ..moveTo(-20, 6)
    ..quadraticBezierTo(-26, 24, -4, 24)
    ..lineTo(8, 24)
    ..quadraticBezierTo(24, 24, 26, 8)
    ..lineTo(32, 0)
    ..lineTo(22, 2)
    ..quadraticBezierTo(14, -4, 4, -2);
  c.drawPath(body, ink.lemon);
  c.drawPath(body, ink.line);
  // Wing.
  c.drawArc(
    const Rect.fromLTWH(-4, 6, 20, 12),
    0.1,
    math.pi * 0.9,
    false,
    ink.line,
  );
  // Head on top, hiding the body line behind it.
  c.drawCircle(const Offset(-8, -8), 12, ink.bg);
  c.drawCircle(const Offset(-8, -8), 12, ink.lemon);
  c.drawCircle(const Offset(-8, -8), 12, ink.line);
  final beak = Path()
    ..moveTo(-19, -9)
    ..lineTo(-29, -6)
    ..lineTo(-19, -3)
    ..close();
  c.drawPath(beak, ink.pink);
  c.drawPath(beak, ink.line);
  c.drawCircle(const Offset(-9, -12), 1.7, ink.dot);
  c.drawCircle(const Offset(-32, -14), 1.8, ink.line);
  c.drawCircle(const Offset(-35, -21), 1.2, ink.line);
}

/// A drink knocked over: cup on its side, a puddle spreading out.
void spilledDrink(Canvas c, DoodleInk ink) {
  c.save();
  c.rotate(-1.15);
  final cup = Path()
    ..moveTo(-11, -10)
    ..lineTo(11, -10)
    ..lineTo(8, 14)
    ..lineTo(-8, 14)
    ..close();
  c.drawPath(cup, ink.line);
  c.drawLine(
    const Offset(-12, -10),
    const Offset(12, -10),
    ink.line..strokeWidth = 2.6,
  );
  ink.line.strokeWidth = 1.8;
  c.drawLine(const Offset(-6, 2), const Offset(6, 2), ink.line);
  c.drawLine(const Offset(2, -10), const Offset(9, -24), ink.line); // straw
  c.restore();
  final puddle = Path()
    ..moveTo(2, 8)
    ..quadraticBezierTo(8, 4, 14, 9)
    ..quadraticBezierTo(24, 6, 26, 14)
    ..quadraticBezierTo(32, 20, 22, 24)
    ..quadraticBezierTo(14, 30, 4, 24)
    ..quadraticBezierTo(-4, 20, 2, 8);
  c.drawPath(puddle, ink.mint);
  c.drawPath(puddle, ink.line);
  c.drawCircle(const Offset(30, 8), 1.6, ink.dot);
  c.drawCircle(const Offset(-6, 26), 1.3, ink.dot);
  c.drawCircle(const Offset(33, 28), 1.0, ink.dot);
}

/// "Disguise": glasses, a nose and a curly mustache.
void disguise(Canvas c, DoodleInk ink) {
  c.drawCircle(const Offset(-10, -4), 8.5, ink.line);
  c.drawCircle(const Offset(10, -4), 8.5, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-1.5, -5)
      ..quadraticBezierTo(0, -8, 1.5, -5),
    ink.line,
  );
  c.drawLine(const Offset(-18.5, -5), const Offset(-24, -8), ink.line);
  c.drawLine(const Offset(18.5, -5), const Offset(24, -8), ink.line);
  c.drawCircle(const Offset(-8, -3), 1.6, ink.dot);
  c.drawCircle(const Offset(12, -3), 1.6, ink.dot);
  c.drawPath(
    Path()
      ..moveTo(0, 2)
      ..lineTo(-3.5, 10)
      ..lineTo(3.5, 10),
    ink.line,
  );
  final stache = Path()
    ..moveTo(0, 14)
    ..quadraticBezierTo(-6, 9, -13, 13)
    ..quadraticBezierTo(-20, 17, -22, 10)
    ..quadraticBezierTo(-23, 22, -11, 21)
    ..quadraticBezierTo(-4, 21, 0, 17)
    ..quadraticBezierTo(4, 21, 11, 21)
    ..quadraticBezierTo(23, 22, 22, 10)
    ..quadraticBezierTo(20, 17, 13, 13)
    ..quadraticBezierTo(6, 9, 0, 14);
  c.drawPath(stache, ink.pink);
  c.drawPath(stache, ink.line);
}

/// An angel who is clearly not good at it: crooked halo, tiny wings, a wink.
void goofyAngel(Canvas c, DoodleInk ink) {
  Path wing() => Path()
    ..moveTo(14, 4)
    ..quadraticBezierTo(24, -8, 36, -10)
    ..quadraticBezierTo(37, -4, 33, -1)
    ..quadraticBezierTo(37, 2, 32, 6)
    ..quadraticBezierTo(33, 11, 26, 12)
    ..quadraticBezierTo(21, 14, 14, 10);
  c.drawPath(wing(), ink.bg);
  c.drawPath(wing(), ink.line);
  c.save();
  c.scale(-1, 1);
  c.drawPath(wing(), ink.bg);
  c.drawPath(wing(), ink.line);
  c.restore();
  c.drawCircle(const Offset(0, 4), 17, ink.bg);
  c.drawCircle(const Offset(0, 4), 17, ink.line);
  c.save();
  c.translate(3, -19);
  c.rotate(-0.28);
  c.drawOval(const Rect.fromLTWH(-12, -4, 24, 8), ink.lemon);
  c.drawOval(const Rect.fromLTWH(-12, -4, 24, 8), ink.line);
  c.restore();
  c.drawPath(
    Path()
      ..moveTo(-10, 0)
      ..quadraticBezierTo(-6, -4, -2, 0),
    ink.line,
  ); // wink ^
  c.drawCircle(const Offset(7, 0), 2.6, ink.line);
  c.drawCircle(const Offset(7.6, 0.4), 1.1, ink.dot);
  final tongue = Path()
    ..moveTo(1, 12)
    ..lineTo(1, 16)
    ..quadraticBezierTo(4.5, 20, 8, 16)
    ..lineTo(8, 11);
  c.drawPath(tongue, ink.pink);
  c.drawPath(tongue, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-8, 10)
      ..quadraticBezierTo(0, 15, 10, 9),
    ink.line,
  );
}

/// Pizza slice: dripping cheese, pepperoni, and a crust that has seen things.
void pizza(Canvas c, DoodleInk ink) {
  final slice = polyPath(const [
    Offset(-18, -14),
    Offset(18, -14),
    Offset(0, 26),
  ]);
  final cheese = Path()
    ..moveTo(-18, -14)
    ..lineTo(18, -14)
    ..lineTo(0, 26)
    ..close();
  c.drawPath(cheese, ink.lemon);
  c.drawPath(slice, ink.line);
  // Crust.
  c.drawPath(
    Path()
      ..moveTo(-20, -18)
      ..quadraticBezierTo(0, -24, 20, -18),
    ink.line..strokeWidth = 3.2,
  );
  ink.line.strokeWidth = 1.8;
  // Dripping cheese at the tip.
  c.drawPath(teardropPath(const Offset(-2, 20), 9, 2.4), ink.lemon);
  c.drawPath(teardropPath(const Offset(-2, 20), 9, 2.4), ink.line);
  for (final p in const [Offset(-7, -5), Offset(6, -7), Offset(-1, 5)]) {
    c.drawCircle(p, 3.6, ink.pink);
    c.drawCircle(p, 3.6, ink.line..strokeWidth = 1.4);
  }
  ink.line.strokeWidth = 1.8;
  // A stretchy cheese string.
  c.drawPath(
    Path()
      ..moveTo(14, -2)
      ..cubicTo(26, 4, 22, 14, 30, 18),
    ink.line,
  );
}

/// Sound asleep: drool bubble, a few Zs.
void sleepyFace(Canvas c, DoodleInk ink) {
  c.drawCircle(const Offset(-4, 4), 19, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-15, -2)
      ..quadraticBezierTo(-11, 2, -7, -2),
    ink.line,
  );
  c.drawPath(
    Path()
      ..moveTo(1, -3)
      ..quadraticBezierTo(5, 1, 9, -3),
    ink.line,
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(-5, 12), width: 8, height: 6),
    ink.line,
  );
  c.drawCircle(const Offset(5, 14), 3.4, ink.mint); // drool bubble
  c.drawCircle(const Offset(5, 14), 3.4, ink.line..strokeWidth = 1.3);
  ink.line.strokeWidth = 1.8;
  // Zzz
  for (final z in const [
    [Offset(18, -14), 5.0],
    [Offset(26, -24), 7.0],
  ]) {
    final o = z[0] as Offset;
    final r = z[1] as double;
    c.drawPath(
      polyPath([
        o + Offset(-r, -r),
        o + Offset(r, -r),
        o + Offset(-r, r),
        o + Offset(r, r),
      ], close: false),
      ink.line..strokeWidth = 1.6,
    );
  }
  ink.line.strokeWidth = 1.8;
}

/// A banana that knows exactly what it is about to do to someone.
void banana(Canvas c, DoodleInk ink) {
  c.save();
  c.rotate(-0.25);
  final fruit = Path()
    ..moveTo(-22, -8)
    ..quadraticBezierTo(-12, 28, 22, 6)
    ..quadraticBezierTo(24, 2, 21, -2)
    ..quadraticBezierTo(0, 18, -16, -12)
    ..quadraticBezierTo(-21, -13, -22, -8);
  c.drawPath(fruit, ink.lemon);
  c.drawPath(fruit, ink.line);
  c.drawPath(
    Path()
      ..moveTo(-16, -4)
      ..quadraticBezierTo(-4, 16, 14, 4),
    ink.line..strokeWidth = 1.2,
  );
  ink.line.strokeWidth = 1.8;
  // Stem and tip.
  c.drawPath(
    polyPath(const [
      Offset(-17, -12),
      Offset(-20, -19),
      Offset(-14, -20),
      Offset(-13, -13),
    ]),
    ink.line,
  );
  c.drawCircle(const Offset(22, 2), 1.6, ink.dot);
  // Cheeky face.
  c.drawCircle(const Offset(-7, 7), 1.3, ink.dot);
  c.drawCircle(const Offset(1, 9), 1.3, ink.dot);
  c.drawPath(
    Path()
      ..moveTo(-6, 13)
      ..quadraticBezierTo(-2, 16, 3, 13),
    ink.line..strokeWidth = 1.3,
  );
  ink.line.strokeWidth = 1.8;
  c.restore();
  // Whoosh: someone is about to slip.
  c.drawLine(const Offset(18, 16), const Offset(30, 14), ink.line);
  c.drawLine(const Offset(20, 22), const Offset(34, 22), ink.line);
  c.drawLine(const Offset(17, 28), const Offset(28, 30), ink.line);
}

/// An ice cream cone that is melting and not happy about it.
void meltingScoop(Canvas c, DoodleInk ink) {
  // The cone underneath.
  final cone = polyPath(const [Offset(-13, 10), Offset(13, 10), Offset(0, 40)]);
  c.drawPath(cone, ink.lemon);
  c.drawPath(cone, ink.line);
  // The scoop, drooping over its edge.
  final scoop = Path()
    ..moveTo(-20, 8)
    ..quadraticBezierTo(-22, -20, 0, -20)
    ..quadraticBezierTo(22, -20, 20, 8)
    ..quadraticBezierTo(24, 14, 18, 13)
    ..quadraticBezierTo(16, 26, 12, 13)
    ..quadraticBezierTo(8, 18, 4, 13)
    ..quadraticBezierTo(-1, 22, -5, 13)
    ..quadraticBezierTo(-11, 17, -13, 13)
    ..quadraticBezierTo(-17, 24, -18, 13)
    ..quadraticBezierTo(-24, 13, -20, 8);
  c.drawPath(scoop, ink.pink);
  c.drawPath(scoop, ink.line);
  eyeAt(c, ink, const Offset(-7, -6), 4, const Offset(0.8, 1.5), 1.6);
  eyeAt(c, ink, const Offset(7, -6), 4, const Offset(-0.8, 1.5), 1.6);
  c.drawPath(
    Path()
      ..moveTo(-6, 3)
      ..quadraticBezierTo(0, -1, 6, 3),
    ink.line,
  ); // worried
  c.drawPath(teardropPath(const Offset(13, -2), 6, 2.2), ink.mint);
  c.drawPath(
    teardropPath(const Offset(13, -2), 6, 2.2),
    ink.line..strokeWidth = 1.2,
  );
  ink.line.strokeWidth = 1.8;
}

/// A smiling jellyfish among scattered ticks, traced from the owner's own
/// marker drawing, wobbles and all, on the same cream paper. Unlike the other
/// doodles its colours are the drawing itself, so it ignores the ink. The
/// sheet is 100 across.
void jellyfish(Canvas c, DoodleInk _) {
  const yellow = Color(0xFFFDD835);
  const blue = Color(0xFF1E88E5);
  const red = Color(0xFFE53935);
  const orange = Color(0xFFFB8C00);
  const green = Color(0xFF43A047);

  c.drawCircle(
    const Offset(50, 50),
    64,
    Paint()..color = const Color(0xFFF6F1E7),
  );

  void line(Color colour, List<double> xy) {
    final pts = [
      for (var i = 0; i + 1 < xy.length; i += 2) Offset(xy[i], xy[i + 1]),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2
        ..color = colour,
    );
  }

  void dot(Color colour, double x, double y, double r) =>
      c.drawCircle(Offset(x, y), r, Paint()..color = colour);

  // The bell: over the top, the double line on the left, then the scalloped
  // edge along the bottom.
  line(yellow, const [
    22.8,
    32,
    25,
    26.5,
    30,
    21.5,
    35,
    18,
    38.5,
    16,
    47,
    15.2,
    54,
    15,
    60,
    15.5, //
    68, 19, 74, 24, 78, 29.5, 80.5, 35, 80.8, 37.5,
  ]);
  line(yellow, const [41, 19, 34, 21.5, 29, 24.5, 26, 28.5, 23.8, 32]);
  line(yellow, const [78.5, 36.5, 79, 39.5, 77.5, 44.5]);
  line(yellow, const [
    79.5,
    43.2,
    77,
    45.5,
    73.5,
    44,
    69,
    41,
    64,
    40.8,
    59,
    43,
    54.5,
    46,
    48,
    45.5, //
    43,
    43,
    39.5,
    39.5,
    35,
    38.5,
    30.5,
    41.5,
    27,
    44.5,
    23,
    43.5,
    21.2,
    41,
    22,
    36.5, //
    24, 32,
  ]);

  // The face.
  dot(blue, 42, 26, 1.5);
  dot(blue, 60.3, 26.8, 1.8);
  line(blue, const [45, 33.2, 47.5, 35, 51, 36.5, 54.5, 35.2, 56, 32.2]);

  // The tentacles.
  line(blue, const [
    23.3,
    44.8,
    27,
    47.5,
    29.5,
    51,
    29,
    56,
    27.2,
    61,
    26.8,
    65,
    30,
    70,
    31.5,
    72, //
    30.2, 77, 30.5, 81, 31.5, 82.2,
  ]);
  line(red, const [
    41.2,
    43.5,
    45,
    47.5,
    46,
    52,
    44,
    58,
    44,
    63,
    47,
    69,
    49,
    73.5,
    46.5,
    80,
    46,
    83.5, //
    47.2, 85.8, 50.2, 85,
  ]);
  line(red, const [
    57.2,
    44.7,
    60,
    48,
    63,
    53,
    62.5,
    58,
    60,
    64,
    60,
    69,
    64,
    74.5,
    65.5,
    79,
    66,
    84, //
    65.5, 85.5,
  ]);
  line(green, const [
    70.8,
    45.3,
    74.5,
    48.5,
    76.2,
    52.5,
    75.2,
    58.5,
    73,
    64.5,
    75,
    69,
    76.8,
    74,
    77,
    78, //
    76.2, 81,
  ]);

  // Everything scattered around it.
  line(orange, const [32.3, 7.3, 37, 8.5, 42, 10.8, 44, 6.2, 47.2, 4]);
  dot(orange, 10.8, 12.5, 1.6);
  dot(orange, 88.3, 10.2, 1.7);
  line(orange, const [85.8, 29.3, 89, 33, 91.8, 36.8, 92.5, 30, 96.3, 22]);
  line(orange, const [3.3, 51.6, 6.5, 54.5, 9, 57.5, 10, 53, 11.8, 49.8]);
  line(green, const [83.8, 70, 88.5, 73.7]);
  line(green, const [95.2, 59.5, 91.5, 66, 87, 71.5, 88.5, 73.7]);
  line(green, const [5.2, 85.3, 8, 87, 11, 89.2, 10.5, 84, 12.2, 80]);
  line(green, const [83.5, 87.3, 88, 89.5, 90.5, 93.3]);
  line(red, const [23.5, 93.5, 27, 95.5, 32.2, 98.5]);
  line(red, const [24.5, 93.5, 26, 94]);
  line(red, const [29.5, 96.5, 30.5, 93.5, 28.5, 93.2]);
}
