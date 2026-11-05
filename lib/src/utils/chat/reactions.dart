import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// The six reactions, in the order the picker shows them. [name] is what
/// the server stores (backend `REACTIONS` in app/api/ws.py).
enum Reaction {
  okay('Thumbs up'),
  happy('Laughing'),
  celebrate('Celebrate'),
  angry('Angry'),
  wow('Wow'),
  cooked('Cooked');

  const Reaction(this.label);

  final String label;

  static Reaction? parse(String? raw) {
    for (final r in values) {
      if (r.name == raw) return r;
    }
    return null;
  }
}

/// A message's reactions (user id → reaction), from how they are stored
/// ("userId:reaction").
Map<String, Reaction> reactionsFrom(List<String>? stored) {
  final out = <String, Reaction>{};
  for (final entry in stored ?? const <String>[]) {
    final i = entry.lastIndexOf(':');
    if (i <= 0) continue;
    final r = Reaction.parse(entry.substring(i + 1));
    if (r != null) out[entry.substring(0, i)] = r;
  }
  return out;
}

/// Encodes [reactions] for storing on a message.
List<String>? reactionsTo(Map<String, Reaction> reactions) {
  if (reactions.isEmpty) return null;
  return [for (final e in reactions.entries) '${e.key}:${e.value.name}']
    ..sort();
}

// ------------------------------------------------------------- drawings ---

const _ink = Color(0xFF1C2440);
const _lemon = Color(0xFFF4D35E);
const _peach = Color(0xFFF8B26A);
const _red = Color(0xFFF27A6B);
const _pink = Color(0xFFF59AC6);
const _mint = Color(0xFF6FD3C0);
const _sky = Color(0xFF8FB7F2);
const _bone = Color(0xFFF4F1E8);

/// A reaction, drawn as a doodle in the sticker style: a navy marker line
/// over flat, warm colours.
class ReactionDoodle extends StatelessWidget {
  const ReactionDoodle(this.reaction, {super.key, this.size = 28});

  final Reaction reaction;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _ReactionPainter(reaction)),
  );
}

class _ReactionPainter extends CustomPainter {
  _ReactionPainter(this.reaction);

  final Reaction reaction;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 100 × 100 grid.
    canvas.scale(size.width / 100, size.height / 100);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _ink;
    Paint fill(Color c) => Paint()..color = c;
    final dot = Paint()..color = _ink;

    void face(Color c) {
      canvas.drawCircle(const Offset(50, 52), 40, fill(c));
      canvas.drawCircle(const Offset(50, 52), 40, line);
    }

    switch (reaction) {
      case Reaction.okay:
        // A thumbs up.
        final cuff = RRect.fromLTRBR(14, 50, 30, 90, const Radius.circular(4));
        canvas.drawRRect(cuff, fill(_sky));
        canvas.drawRRect(cuff, line);
        final thumb = Path()
          ..moveTo(38, 52)
          ..lineTo(39, 38)
          ..quadraticBezierTo(41, 24, 53, 25)
          ..quadraticBezierTo(66, 26, 64, 39)
          ..lineTo(62, 48);
        canvas.drawPath(thumb, fill(_lemon));
        canvas.drawPath(thumb, line);
        final fist = RRect.fromLTRBR(28, 46, 80, 90, const Radius.circular(12));
        canvas.drawRRect(fist, fill(_lemon));
        canvas.drawRRect(fist, line);
        // The curled fingers.
        for (final y in const [58.0, 68.0, 78.0]) {
          canvas.drawLine(Offset(80, y), Offset(64, y), line);
        }
      case Reaction.happy:
        // Laughing so hard it brings tears: 😂.
        face(_lemon);
        // Eyes squeezed shut.
        for (final x in const [34.0, 66.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(x - 10, 44)
              ..quadraticBezierTo(x, 32, x + 10, 44),
            line,
          );
        }
        // A wide open mouth with a row of teeth.
        final mouth = Path()
          ..moveTo(26, 56)
          ..lineTo(74, 56)
          ..quadraticBezierTo(72, 92, 50, 90)
          ..quadraticBezierTo(28, 92, 26, 56)
          ..close();
        canvas.drawPath(mouth, fill(_ink));
        canvas.save();
        canvas.clipPath(mouth);
        canvas.drawRect(
          const Rect.fromLTRB(20, 56, 80, 65),
          fill(Colors.white),
        );
        canvas.drawCircle(const Offset(50, 90), 11, fill(_red));
        canvas.restore();
        canvas.drawPath(mouth, line);
        // Tears flying out on both sides.
        for (final side in const [-1.0, 1.0]) {
          final x = 50 + side * 38;
          final tear = Path()
            ..moveTo(50 + side * 24, 46)
            ..quadraticBezierTo(x + side * 10, 50, x + side * 6, 62)
            ..arcToPoint(
              Offset(x - side * 8, 58),
              radius: const Radius.circular(8),
              clockwise: side > 0,
            )
            ..close();
          canvas.drawPath(tear, fill(_sky));
          canvas.drawPath(tear, line);
        }
      case Reaction.celebrate:
        // A party popper, confetti flying out.
        final cone = Path()
          ..moveTo(16, 88)
          ..lineTo(36, 34)
          ..lineTo(70, 68)
          ..close();
        canvas.drawPath(cone, fill(_peach));
        canvas.save();
        canvas.clipPath(cone);
        for (var i = 0; i < 4; i++) {
          canvas.drawLine(
            Offset(10.0 + i * 14, 60),
            Offset(40.0 + i * 14, 92),
            Paint()
              ..strokeWidth = 5
              ..color = _red,
          );
        }
        canvas.restore();
        canvas.drawPath(cone, line);
        canvas.drawPath(
          Path()
            ..moveTo(58, 38)
            ..quadraticBezierTo(66, 22, 60, 12)
            ..quadraticBezierTo(76, 18, 80, 8),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..color = _pink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(70, 50)
            ..quadraticBezierTo(84, 46, 92, 32),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..color = _mint,
        );
        for (final (x, y, colour) in const [
          (48.0, 18.0, _mint),
          (84.0, 60.0, _pink),
          (88.0, 18.0, _sky),
          (72.0, 32.0, _lemon),
        ]) {
          canvas.drawCircle(Offset(x, y), 5, fill(colour));
        }
      case Reaction.angry:
        face(_red);
        // Brows down to the middle.
        canvas.drawLine(const Offset(24, 34), const Offset(44, 44), line);
        canvas.drawLine(const Offset(76, 34), const Offset(56, 44), line);
        canvas.drawCircle(const Offset(36, 50), 5, dot);
        canvas.drawCircle(const Offset(64, 50), 5, dot);
        canvas.drawPath(
          Path()
            ..moveTo(34, 76)
            ..quadraticBezierTo(50, 62, 66, 76),
          line,
        );
        // A puff of steam.
        canvas.drawPath(
          Path()
            ..moveTo(84, 14)
            ..quadraticBezierTo(90, 20, 84, 26)
            ..quadraticBezierTo(78, 32, 86, 36),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..color = _bone,
        );
      case Reaction.wow:
        face(_lemon);
        for (final x in const [34.0, 66.0]) {
          canvas.drawCircle(Offset(x, 44), 10, fill(Colors.white));
          canvas.drawCircle(Offset(x, 44), 10, line);
          canvas.drawCircle(Offset(x, 46), 4, dot);
          canvas.drawPath(
            Path()
              ..moveTo(x - 10, 26)
              ..quadraticBezierTo(x, 18, x + 10, 26),
            line,
          );
        }
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(50, 74), width: 18, height: 22),
          fill(_ink),
        );
      case Reaction.cooked:
        // A skull: you've been cooked.
        final head = Path()
          ..moveTo(18, 54)
          ..cubicTo(14, 14, 86, 14, 82, 54)
          ..lineTo(74, 66)
          ..lineTo(74, 86)
          ..lineTo(26, 86)
          ..lineTo(26, 66)
          ..close();
        canvas.drawPath(head, fill(_bone));
        canvas.drawPath(head, line);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(36, 50), width: 18, height: 20),
          fill(_ink),
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(64, 50), width: 18, height: 20),
          fill(_ink),
        );
        canvas.drawPath(
          Path()
            ..moveTo(50, 60)
            ..lineTo(45, 70)
            ..lineTo(55, 70)
            ..close(),
          fill(_ink),
        );
        for (final x in const [38.0, 50.0, 62.0]) {
          canvas.drawLine(Offset(x, 76), Offset(x, 86), line);
        }
    }
  }

  @override
  bool shouldRepaint(_ReactionPainter old) => old.reaction != reaction;
}

// ------------------------------------------------------------- on screen ---

/// The badge on a message's bottom-right corner: each reaction once (most
/// used first, up to three) and how many people reacted, when more than one.
class ReactionBadge extends StatelessWidget {
  const ReactionBadge({super.key, required this.reactions, this.myId});

  final Map<String, Reaction> reactions;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final counts = <Reaction, int>{};
    for (final r in reactions.values) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    final kinds = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final mine = myId != null && reactions.containsKey(myId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mine ? AppColors.primary : AppColors.lineSoft,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in kinds.take(3)) ...[
            ReactionDoodle(r, size: 18),
            const SizedBox(width: 2),
          ],
          if (reactions.length > 1) ...[
            const SizedBox(width: 2),
            Text(
              '${reactions.length}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The first row of a message's long-press sheet: the six reactions. The
/// one you already chose is ringed; picking it again takes it away.
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({
    super.key,
    required this.current,
    required this.onPick,
  });

  final Reaction? current;
  final ValueChanged<Reaction> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final r in Reaction.values)
            Tooltip(
              message: r.label,
              child: GestureDetector(
                key: ValueKey('react-${r.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: r == current
                        ? AppColors.primary.withValues(alpha: 0.25)
                        : Colors.transparent,
                    border: Border.all(
                      color: r == current
                          ? AppColors.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: ReactionDoodle(r, size: 40),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
