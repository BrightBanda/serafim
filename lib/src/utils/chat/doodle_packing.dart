import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/doodle_catalogue.dart';
import 'package:serafim/src/utils/chat/doodle_layout.g.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// One doodle placed on the wallpaper tile.
class PlacedDoodle {
  const PlacedDoodle(
    this.doodle,
    this.at,
    this.rotation,
    this.scale,
    this.bounds,
  );

  final Doodle doodle;

  /// Where the middle of the doodle's ink goes, in tile coordinates.
  final Offset at;
  final double rotation;
  final double scale;
  final DoodleBounds bounds;

  /// Radius of a circle around the placed doodle that contains all of it.
  double get radius => bounds.radius * scale;
}

/// Packs doodles into a tile so that none touch.
///
/// Every doodle is wrapped in the circle measured for it, and a new doodle is
/// only accepted where its circle clears every existing one by at least
/// [gap]. The tile wraps around (a doodle leaving the right edge re-enters on
/// the left), so tiles can be repeated seamlessly and the seams are as clean
/// as the middle.
///
/// The layout is seeded, so it is identical on every launch and never shuffles
/// when the screen resizes or the keyboard opens.
class DoodleLayout {
  DoodleLayout._(this.width, this.height, this.items);

  final double width;
  final double height;
  final List<PlacedDoodle> items;

  static const double defaultWidth = 520;
  static const double defaultHeight = 800;

  static final Map<String, DoodleLayout> _cache = {};
  static DoodleLayout? _standard;

  /// The shipped layout: precomputed (see `doodle_layout.g.dart`), so showing
  /// the wallpaper costs nothing — no packing happens at runtime.
  static DoodleLayout standard() => _standard ??= _fromData();

  static DoodleLayout _fromData() {
    final byName = {for (final d in allDoodles) d.name: d};
    return DoodleLayout._(
      doodleLayoutWidth,
      doodleLayoutHeight,
      List.unmodifiable([
        for (final e in doodleLayoutData)
          if (byName[e.$1] case final d?)
            PlacedDoodle(d, Offset(e.$2, e.$3), e.$4, e.$5, boundsOf(d)),
      ]),
    );
  }

  /// Runs the packing algorithm. Used to (re)generate `doodle_layout.g.dart`
  /// and by tests; the app itself uses [standard].
  static DoodleLayout fresh({int seed = 7, double gap = 5}) => build(
    width: defaultWidth,
    height: defaultHeight,
    seed: seed,
    gap: gap,
    cache: false,
  );

  static DoodleLayout build({
    required double width,
    required double height,
    required int seed,
    required double gap,
    List<Doodle>? big,
    List<Doodle>? fillers,
    bool cache = true,
  }) {
    DoodleLayout pack() => _pack(
      width,
      height,
      math.Random(seed),
      gap,
      big ?? bigDoodles,
      fillers ?? fillerDoodles,
    );
    if (!cache) return pack();
    final key = '$width/$height/$seed/$gap/${big?.length}/${fillers?.length}';
    return _cache[key] ??= pack();
  }

  static DoodleLayout _pack(
    double w,
    double h,
    math.Random rnd,
    double gap,
    List<Doodle> big,
    List<Doodle> fillers,
  ) {
    final placed = <PlacedDoodle>[];

    double wrapDelta(double a, double b, double size) {
      final d = (a - b).abs();
      return math.min(d, size - d);
    }

    /// Distance between the edges of two circles (negative = overlapping).
    double clearance(Offset at, double r, PlacedDoodle other) {
      final dx = wrapDelta(at.dx, other.at.dx, w);
      final dy = wrapDelta(at.dy, other.at.dy, h);
      return math.sqrt(dx * dx + dy * dy) - r - other.radius;
    }

    /// Tries to place [d], sampling [tries] spots and keeping the roomiest.
    bool tryPlace(Doodle d, double scale, int tries, {bool avoidSame = false}) {
      final b = boundsOf(d);
      final r = b.radius * scale;
      Offset? best;
      var bestRoom = -1.0;
      for (var i = 0; i < tries; i++) {
        final at = Offset(rnd.nextDouble() * w, rnd.nextDouble() * h);
        var room = double.infinity;
        var ok = true;
        for (final o in placed) {
          final c = clearance(at, r, o);
          if (c < gap) {
            ok = false;
            break;
          }
          // Keep two of the same doodle from sitting side by side.
          if (avoidSame && o.doodle.name == d.name && c < 90) {
            ok = false;
            break;
          }
          room = math.min(room, c);
        }
        if (ok && room > bestRoom) {
          bestRoom = room;
          best = at;
        }
      }
      if (best == null) return false;
      placed.add(
        PlacedDoodle(d, best, (rnd.nextDouble() - 0.5) * 0.8, scale, b),
      );
      return true;
    }

    // Every big doodle gets one guaranteed spot, largest first so the big ones
    // are not squeezed out; then the same doodles are repeated at random
    // (never side by side) until the tile is full.
    final bySize = [...big]
      ..sort((a, b) => boundsOf(b).radius.compareTo(boundsOf(a).radius));
    for (final d in bySize) {
      tryPlace(d, 0.95 + rnd.nextDouble() * 0.1, 400, avoidSame: true);
    }
    var failures = 0;
    var deck = <Doodle>[];
    while (failures < 90) {
      if (deck.isEmpty) deck = [...big]..shuffle(rnd);
      final d = deck.removeLast();
      final scale = 0.9 + rnd.nextDouble() * 0.2;
      if (tryPlace(d, scale, 70, avoidSame: true)) {
        failures = 0;
      } else {
        failures++;
      }
    }

    // Then the small fillers soak up whatever gaps are left.
    failures = 0;
    deck = [];
    while (failures < 500) {
      if (deck.isEmpty) deck = [...fillers]..shuffle(rnd);
      final d = deck.removeLast();
      final scale = 0.9 + rnd.nextDouble() * 0.5;
      if (tryPlace(d, scale, 90)) {
        failures = 0;
      } else {
        failures++;
      }
    }

    return DoodleLayout._(w, h, List.unmodifiable(placed));
  }

  /// Smallest edge-to-edge gap between any two placed doodles (wrap-aware).
  double get tightestGap {
    var tightest = double.infinity;
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final a = items[i], b = items[j];
        final dx = math.min(
          (a.at.dx - b.at.dx).abs(),
          width - (a.at.dx - b.at.dx).abs(),
        );
        final dy = math.min(
          (a.at.dy - b.at.dy).abs(),
          height - (a.at.dy - b.at.dy).abs(),
        );
        tightest = math.min(
          tightest,
          math.sqrt(dx * dx + dy * dy) - a.radius - b.radius,
        );
      }
    }
    return tightest;
  }

  /// Fraction of the tile covered by the doodles' bounding circles.
  double get coverage {
    final area = items.fold<double>(
      0,
      (sum, p) => sum + math.pi * p.radius * p.radius,
    );
    return area / (width * height);
  }
}

/// The chat wallpaper: a packed, repeating tile of goofy doodles.
class ChatDoodlePainter extends CustomPainter {
  ChatDoodlePainter(this.palette, {DoodleLayout? layout})
    : layout = layout ?? DoodleLayout.standard();

  final AppPalette palette;
  final DoodleLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.paper);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final ink = DoodleInk(palette);
    final tilesX = (size.width / layout.width).ceil() + 1;
    final tilesY = (size.height / layout.height).ceil() + 1;

    for (var ty = -1; ty < tilesY; ty++) {
      for (var tx = -1; tx < tilesX; tx++) {
        final origin = Offset(tx * layout.width, ty * layout.height);
        for (final p in layout.items) {
          final at = origin + p.at;
          // Skip doodles that are entirely off-screen.
          if (at.dx + p.radius < 0 ||
              at.dy + p.radius < 0 ||
              at.dx - p.radius > size.width ||
              at.dy - p.radius > size.height) {
            continue;
          }
          canvas.save();
          canvas.translate(at.dx, at.dy);
          canvas.rotate(p.rotation);
          canvas.scale(p.scale);
          // Doodles are drawn around their own origin; the measured centre of
          // their ink is what was placed, so shift it back.
          canvas.translate(-p.bounds.cx, -p.bounds.cy);
          p.doodle.draw(canvas, ink);
          canvas.restore();
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChatDoodlePainter old) => !identical(old.palette, palette);
}
