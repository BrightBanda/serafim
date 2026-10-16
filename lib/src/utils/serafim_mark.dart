import 'package:flutter/material.dart';

/// The Serafim logo: a white "S" built from three angular slabs, tilted up,
/// on an indigo-violet rounded tile with a hard navy offset shadow.
///
/// Drawn in code from the same geometry as the app icon (see `assets/icon/`),
/// so it is sharp at any size. The colors are fixed brand colors, not the
/// light/dark palette: it is the same logo in both themes.
class SerafimMark extends StatelessWidget {
  const SerafimMark({super.key, this.size = 28, this.tile = true});

  final double size;

  /// Draw the rounded tile behind the S. Without it only the S is drawn.
  final bool tile;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Serafim',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: SerafimMarkPainter(tile: tile)),
      ),
    );
  }
}

class SerafimMarkPainter extends CustomPainter {
  const SerafimMarkPainter({this.tile = true});

  final bool tile;

  static const tileTop = Color(0xFF7B72E4);
  static const tileBottom = Color(0xFF4D44B6);
  static const border = Color(0xFF221F55);
  static const shadow = Color(0xFF221F55);
  static const topSlab = Color(0xFFFFFFFF);
  static const spineSlab = Color(0xFFDAD6FB);
  static const bottomSlab = Color(0xFFBDB6F6);

  /// The three slabs (top, spine, bottom) on a 256 x 256 grid, exactly as in
  /// the approved logo and the launcher icon.
  static const List<List<Offset>> slabs = [
    [
      Offset(101.6, 61.38),
      Offset(197.38, 37.5),
      Offset(165.42, 90.68),
      Offset(69.65, 114.56),
    ],
    [
      Offset(69.65, 114.56),
      Offset(122.86, 101.29),
      Offset(181.35, 136.44),
      Offset(128.14, 149.71),
    ],
    [
      Offset(149.4, 189.62),
      Offset(53.62, 213.5),
      Offset(85.58, 160.32),
      Offset(181.35, 136.44),
    ],
  ];

  static const double _grid = 256;
  static const double _shadowOffset = 5;

  Path _path(List<Offset> pts, double k, [Offset shift = Offset.zero]) {
    final path = Path()
      ..moveTo(pts.first.dx * k + shift.dx, pts.first.dy * k + shift.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx * k + shift.dx, p.dy * k + shift.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / _grid;

    if (tile) {
      final inset = 3 * k;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          inset,
          inset,
          size.width - 2 * inset,
          size.height - 2 * inset,
        ),
        Radius.circular(56 * k),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tileTop, tileBottom],
          ).createShader(Offset.zero & size),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * k
          ..color = border,
      );
    }

    final shadowShift = Offset(_shadowOffset * k, _shadowOffset * k);
    for (final slab in slabs) {
      canvas.drawPath(_path(slab, k, shadowShift), Paint()..color = shadow);
    }
    // Spine first so the top and bottom slabs overlap its ends cleanly.
    canvas.drawPath(_path(slabs[1], k), Paint()..color = spineSlab);
    canvas.drawPath(_path(slabs[0], k), Paint()..color = topSlab);
    canvas.drawPath(_path(slabs[2], k), Paint()..color = bottomSlab);
  }

  @override
  bool shouldRepaint(SerafimMarkPainter old) => old.tile != tile;
}
