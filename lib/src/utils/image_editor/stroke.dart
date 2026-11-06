import 'package:flutter/material.dart';

/// What a line is drawn with.
enum Brush {
  /// An even, solid line.
  pen,

  /// Wider and slightly see-through.
  marker,

  /// Very wide and see-through, for colouring over things.
  highlighter,

  /// Thin when fast and at the ends, thick when slow: like a brush pen.
  ink;

  /// The name that travels between phones; anything unknown is a [pen].
  static Brush parse(Object? name) =>
      Brush.values.firstWhere((b) => b.name == name, orElse: () => Brush.pen);
}

/// How much a line is steadied as it is drawn.
enum DrawSmoothing {
  off(1, 'Off'),
  light(0.45, 'Light'),
  strong(0.2, 'Strong');

  const DrawSmoothing(this.follow, this.label);

  /// How far the line moves towards the finger with each new position.
  final double follow;
  final String label;

  DrawSmoothing get next => values[(index + 1) % values.length];
}

/// Steadies a shaky finger: the line follows it a little behind, so small
/// wobbles never reach the page. What comes out is an ordinary list of points,
/// so the other phone gets the steadied line and needs no smoothing of its own.
class StrokeSmoother {
  StrokeSmoother(this.smoothing, Offset start) : _at = start;

  final DrawSmoothing smoothing;
  Offset _at;

  /// The next point of the line, for the finger being at [finger].
  Offset follow(Offset finger) => _at += (finger - _at) * smoothing.follow;
}

/// One freehand line drawn on a picture, or (with [sticker] set) a sticker
/// stuck on it. Points are in the coordinates of the on-screen picture; [width]
/// is the on-screen thickness.
class Stroke {
  Stroke({
    required this.color,
    required this.width,
    List<Offset>? points,
    this.erase = false,
    this.brush = Brush.pen,
    this.sticker,
    this.stickerSize = 0,
    this.stickerRotation = 0,
  }) : points = points ?? [];

  /// A sticker placed at [at]: [size] across, turned by [rotation] radians.
  factory Stroke.sticker(
    String id, {
    required Offset at,
    required double size,
    double rotation = 0,
  }) => Stroke(
    color: const Color(0x00000000),
    width: 0.01,
    points: [at],
    sticker: id,
    stickerSize: size,
    stickerRotation: rotation,
  );

  final Color color;
  final double width;
  final List<Offset> points;

  /// An eraser stroke: it rubs out the pen strokes under it instead of
  /// painting. (It never touches the picture or paper underneath.)
  final bool erase;

  final Brush brush;

  /// The id of the sticker this is instead of a line; `points.first` is its
  /// centre.
  final String? sticker;
  final double stickerSize;
  final double stickerRotation;
}

/// How thick pens are on a shared sheet, per [drawWidths] unit: a pen of size
/// 8 is `8 / referencePadWidth` of the sheet, whatever the screen.
const double referencePadWidth = 360;

/// How tall a drawing sheet is, per unit of width. Fixed, not fitted to the
/// screen, so two phones drawing together agree. Points on a sheet are measured
/// in sheet widths: x runs 0..1 and y runs 0..[drawSheetAspect].
const double drawSheetAspect = 1.4;

/// The biggest sheet of [aspect] that fits in [available], leaving [margin] on
/// each side.
Size fitDrawSheet(Size available, double aspect, {double margin = 8}) {
  final width = available.width - margin * 2;
  final height = available.height - margin * 2;
  final across = width * aspect <= height ? width : height / aspect;
  return Size(across, across * aspect);
}

/// The seven colours to draw with.
const List<Color> drawColors = [
  Color(0xFFFFFFFF), // white
  Color(0xFF000000), // black
  Color(0xFFE53935), // red
  Color(0xFFFB8C00), // orange
  Color(0xFFFDD835), // yellow
  Color(0xFF43A047), // green
  Color(0xFF1E88E5), // blue
];

/// The three stroke sizes: thin, medium, thick (on-screen logical pixels).
const List<double> drawWidths = [3, 8, 16];

const int defaultColorIndex = 2; // red
const int defaultWidthIndex = 1; // medium

/// The three eraser sizes, in the same units as [drawWidths]: bigger than
/// the pens, since rubbing out wants room.
const List<double> eraserWidths = [8, 20, 44];
const int defaultEraserIndex = 1; // medium

/// The line width for size [index] of the pen, or of the eraser.
double strokeWidthFor(int index, {required bool erase}) =>
    erase ? eraserWidths[index] : drawWidths[index];

/// How much to multiply on-screen lengths by to get picture pixels, so a line
/// that looks 8 px thick on a 360 px wide screen is 8 × (image / 360) px in the
/// saved picture.
double strokeScale({required double displayedWidth, required int imageWidth}) =>
    displayedWidth <= 0 ? 1 : imageWidth / displayedWidth;
