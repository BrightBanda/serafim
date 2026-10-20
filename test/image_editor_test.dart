import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/presentation/view/image_editor_page.dart';
import 'package:serafim/src/utils/image_editor/draw_canvas.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

Uint8List _png(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('exactly seven colours and three stroke sizes', () {
    expect(drawColors, hasLength(7));
    expect(drawWidths, [3, 8, 16]);
    expect(drawColors[defaultColorIndex], const Color(0xFFE53935));
    expect(defaultWidthIndex, 1);
  });

  test('on-screen lengths scale up to picture pixels', () {
    expect(strokeScale(displayedWidth: 360, imageWidth: 1080), 3);
    expect(strokeScale(displayedWidth: 0, imageWidth: 1080), 1);
  });

  testWidgets('drawing: swatches and sizes exist, undo removes a stroke', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ImageEditorPage(bytes: _png(200, 100))),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Draw'));
    // The picture is decoded by the real codec, which needs real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 7; i++) {
      expect(find.byKey(ValueKey('draw-color-$i')), findsOneWidget);
    }
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('draw-size-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('draw-undo')), findsOneWidget);

    IconButton undo() => tester.widget(find.byKey(const ValueKey('draw-undo')));
    expect(undo().onPressed, isNull); // nothing to undo yet

    await tester.drag(
      find.byType(RawImage),
      const Offset(40, 10),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(undo().onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('draw-undo')));
    await tester.pump();
    expect(undo().onPressed, isNull);
  });

  test('flattening keeps the picture size and paints the stroke', () async {
    final codec = await ui.instantiateImageCodec(_png(100, 50));
    final image = (await codec.getNextFrame()).image;
    final stroke = Stroke(
      color: const Color(0xFFFFFFFF),
      width: 10,
      points: [const Offset(10, 12), const Offset(40, 12)],
    );
    // Shown 50 px wide: the picture is 2x, so the line is 20 px thick.
    final bytes = await flattenStrokes(image, [stroke], displayedWidth: 50);
    final out = img.decodePng(bytes)!;
    expect((out.width, out.height), (100, 50));
    final onLine = out.getPixel(
      50,
      24,
    ); // (25,12) on screen = (50,24) in the picture
    expect(onLine.r, 255);
    expect(out.getPixel(5, 2).r, lessThan(100)); // untouched corner
  });
}
