import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// The faces the mascot pulls, one per bounce.
enum LoaderFace { neutral, happy, squint, shout, smile, wide }

/// Where the mascot is at one moment. Worked out from time alone, with nothing
/// allocated but this small record, so it costs next to nothing per frame.
class LoaderPose {
  const LoaderPose({
    required this.lift,
    required this.scaleX,
    required this.scaleY,
    required this.turn,
    required this.face,
    required this.shadow,
    required this.burst,
    required this.fall,
  });

  /// How high: 0 on the floor, 1 at the top of the jump.
  final double lift;

  /// Squash and stretch.
  final double scaleX;
  final double scaleY;

  /// Spin, in radians.
  final double turn;
  final LoaderFace face;

  /// Shadow size: smaller the higher it is.
  final double shadow;

  /// The lines that fly off at take-off, fading 1 to 0.
  final double burst;

  /// The little curved lines while it falls, 0 to 1.
  final double fall;
}

/// How long of each bounce is spent squashed on the floor.
const double _onFloor = 0.24;

double _easeInOut(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

/// The pose at [beats] bounces since the start. Every bounce lands, squashes,
/// leaps, spins once (alternating direction) and lands with a new face.
LoaderPose loaderPoseAt(double beats) {
  final beat = beats.floor();
  final p = beats - beat;
  final face = LoaderFace.values[beat % LoaderFace.values.length];
  if (p < _onFloor) {
    final squash = math.sin(p / _onFloor * math.pi);
    return LoaderPose(
      lift: 0,
      scaleX: 1 + 0.24 * squash,
      scaleY: 1 - 0.32 * squash,
      turn: 0,
      face: face,
      shadow: 1 + 0.12 * squash,
      burst: 0,
      fall: 0,
    );
  }
  final air = (p - _onFloor) / (1 - _onFloor);
  final lift = 4 * air * (1 - air);
  // Fastest, so most stretched, just after leaving and just before landing.
  final speed = (1 - 2 * air).abs();
  final stretch = 0.12 * speed * speed;
  final direction = beat.isEven ? 1 : -1;
  return LoaderPose(
    lift: lift,
    scaleX: 1 - 0.7 * stretch,
    scaleY: 1 + stretch,
    turn: _easeInOut(air) * 2 * math.pi * direction,
    face: face,
    shadow: 1 - 0.55 * lift,
    burst: air < 0.3 ? 1 - air / 0.3 : 0,
    fall: air > 0.62 ? (air - 0.62) / 0.38 : 0,
  );
}

/// Draws the mascot. Plain lines and one rounded square, with no layers, blurs,
/// images or text, so it is cheap on any phone. [repaint] redraws it without
/// rebuilding any widget.
class SerafimLoaderPainter extends CustomPainter {
  SerafimLoaderPainter({
    required this.beats,
    required this.ink,
    required this.accent,
    required this.fill,
  }) : super(repaint: beats);

  /// Bounces so far, as an animation.
  final Animation<double> beats;
  final Color ink;
  final Color accent;
  final Color fill;

  late final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = ink;
  late final _accent = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = accent;
  late final _fill = Paint()..color = fill;
  late final _shadow = Paint()..color = accent.withValues(alpha: 0.55);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final pose = loaderPoseAt(beats.value);
    final box = s * 0.36;
    final floor = s * 0.84;
    final x = size.width / 2;
    _line.strokeWidth = s * 0.03;
    _accent.strokeWidth = s * 0.03;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, floor + s * 0.03),
        width: s * 0.46 * pose.shadow,
        height: s * 0.055 * pose.shadow,
      ),
      _shadow,
    );

    final y = floor - box / 2 * pose.scaleY - pose.lift * s * 0.3;

    if (pose.burst > 0) {
      _burst(canvas, Offset(x, y), s, pose.burst);
    }
    if (pose.fall > 0) _fallLines(canvas, Offset(x, y), s, pose.fall);

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(pose.turn);
    canvas.scale(pose.scaleX, pose.scaleY);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: box, height: box),
      Radius.circular(box * 0.13),
    );
    canvas.drawRRect(body, _fill);
    canvas.drawRRect(body, _line);
    _face(canvas, pose.face, box);
    canvas.restore();
  }

  void _face(Canvas canvas, LoaderFace face, double b) {
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1 * b, y1 * b), Offset(x2 * b, y2 * b), _line);

    switch (face) {
      case LoaderFace.neutral:
        line(-0.15, -0.13, -0.15, 0.1);
        line(0.15, -0.13, 0.15, 0.1);
      case LoaderFace.wide:
        line(-0.15, -0.16, -0.15, 0.14);
        line(0.15, -0.16, 0.15, 0.14);
      case LoaderFace.happy:
        for (final c in const [-0.17, 0.17]) {
          line(c - 0.1, 0.06, c, -0.08);
          line(c, -0.08, c + 0.1, 0.06);
        }
      case LoaderFace.squint:
        line(-0.27, -0.1, -0.09, 0);
        line(-0.09, 0, -0.27, 0.1);
        line(0.27, -0.1, 0.09, 0);
        line(0.09, 0, 0.27, 0.1);
      case LoaderFace.shout:
        line(-0.27, -0.1, -0.09, 0);
        line(-0.09, 0, -0.27, 0.1);
        line(0.07, -0.12, 0.07, 0.12);
        line(0.07, -0.12, 0.29, 0);
        line(0.29, 0, 0.07, 0.12);
      case LoaderFace.smile:
        for (final c in const [-0.17, 0.17]) {
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(c * b, -0.02 * b),
              width: 0.2 * b,
              height: 0.2 * b,
            ),
            0,
            math.pi,
            false,
            _line,
          );
        }
    }
  }

  void _burst(Canvas canvas, Offset c, double s, double amount) {
    _accent.color = accent.withValues(alpha: amount);
    final near = s * (0.32 - 0.05 * amount);
    final far = near + s * 0.09 * amount;
    for (final angle in const [-2.4, -2.0, -1.6]) {
      final d = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(c + d * near, c + d * far, _accent);
    }
    _accent.color = accent;
  }

  void _fallLines(Canvas canvas, Offset c, double s, double amount) {
    _accent.color = accent.withValues(alpha: amount);
    final r = s * 0.28;
    for (final (i, start) in const [0.25, 0.6].indexed) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + i * s * 0.05),
        start,
        0.4,
        false,
        _accent,
      );
    }
    _accent.color = accent;
  }

  @override
  bool shouldRepaint(SerafimLoaderPainter old) =>
      old.beats != beats ||
      old.ink != ink ||
      old.accent != accent ||
      old.fill != fill;
}

/// The loading mascot: it bounces, squashes on the floor, spins, and pulls a new
/// face on every landing. Use in place of a full-page or section spinner.
///
/// One ticker and one repaint, inside its own repaint boundary, so nothing
/// around it redraws or rebuilds. It stops by itself when its page is off
/// screen, and stands still if the phone asks for reduced motion.
class SerafimLoader extends StatefulWidget {
  const SerafimLoader({super.key, this.size = 84, this.onBlack = false});

  final double size;

  /// On a black screen, whatever the app's theme (the drawing pads, the camera).
  final bool onBlack;

  /// How long one bounce takes.
  static const beat = Duration(milliseconds: 950);

  @override
  State<SerafimLoader> createState() => _SerafimLoaderState();
}

class _SerafimLoaderState extends State<SerafimLoader>
    with SingleTickerProviderStateMixin {
  static final _faces = LoaderFace.values.length;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SerafimLoader.beat * _faces,
  );
  late final Animation<double> _beats = _controller.drive(
    Tween(begin: 0, end: _faces.toDouble()),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      // A happy face, standing on the floor.
      _controller.value = 1 / _faces;
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.onBlack || AppColors.paper.computeLuminance() < 0.2;
    return Semantics(
      label: 'Loading',
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('serafim-loader'),
          size: Size.square(widget.size),
          painter: SerafimLoaderPainter(
            beats: _beats,
            ink: dark ? const Color(0xFFE6E2FF) : AppColors.primaryDeep,
            accent: AppColors.primary,
            fill: widget.onBlack ? Colors.black : AppColors.paper,
          ),
        ),
      ),
    );
  }
}
