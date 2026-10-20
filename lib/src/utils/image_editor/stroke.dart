import 'package:flutter/material.dart';

/// One freehand line drawn on a picture. Points are in the coordinates of the
/// on-screen picture; [width] is the on-screen thickness.
class Stroke {
  Stroke({required this.color, required this.width, List<Offset>? points})
    : points = points ?? [];

  final Color color;
  final double width;
  final List<Offset> points;
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

/// How much to multiply on-screen lengths by to get picture pixels, so a line
/// that looks 8 px thick on a 360 px wide screen is 8 × (image / 360) px in the
/// saved picture.
double strokeScale({required double displayedWidth, required int imageWidth}) =>
    displayedWidth <= 0 ? 1 : imageWidth / displayedWidth;
