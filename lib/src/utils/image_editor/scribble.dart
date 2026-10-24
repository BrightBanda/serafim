import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/utils/image_editor/draw_canvas.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

/// The papers a scribble can be drawn on.
const List<Color> scribblePapers = [
  Color(0xFFF6F1E7), // paper
  Color(0xFF14161C), // midnight
  Color(0xFFCFE3F5), // sky
  Color(0xFFF3D9DE), // blush
];

/// Marks a PNG as a scribble. A scribble travels as an ordinary picture, so
/// this label inside the file is how the receiving phone knows to show it as
/// a drawing (whole, not cropped) rather than as a photo or a sticker.
const String scribbleMarkerKey = 'serafim';
const String scribbleMarkerValue = 'scribble';

/// Whether [png] carries the scribble label. The label is written right after
/// the PNG header, so only the start of the file is looked at.
bool hasScribbleMarker(Uint8List png) {
  final head = String.fromCharCodes(
    png.length > 400 ? png.sublist(0, 400) : png,
  );
  return head.contains('tEXt$scribbleMarkerKey\u0000$scribbleMarkerValue');
}

/// Draws [strokes] on a square sheet of [paper], [pixels] across, and returns
/// a labelled PNG. [displayedWidth] is how wide the pad was on screen, so the
/// lines come out the same thickness relative to the sheet.
Future<Uint8List> renderScribble({
  required List<Stroke> strokes,
  required double displayedWidth,
  required Color paper,
  int pixels = 1000,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(pixels.toDouble(), pixels.toDouble());
  canvas.drawRect(Offset.zero & size, Paint()..color = paper);
  StrokePainter(
    strokes: strokes,
    scale: strokeScale(displayedWidth: displayedWidth, imageWidth: pixels),
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels, pixels);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return compute(_label, data!.buffer.asUint8List());
}

Uint8List _label(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) return png;
  decoded.textData = {scribbleMarkerKey: scribbleMarkerValue};
  return Uint8List.fromList(img.encodePng(decoded));
}
