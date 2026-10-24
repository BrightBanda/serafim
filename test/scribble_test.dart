import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/data/services/chat_media_store.dart';
import 'package:serafim/src/presentation/view/scribble_page.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/image_editor/draw_canvas.dart';
import 'package:serafim/src/utils/image_editor/scribble.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

Uint8List _plainPng() {
  final i = img.Image(width: 8, height: 8);
  return Uint8List.fromList(img.encodePng(i));
}

Uint8List _jpg() {
  final i = img.Image(width: 8, height: 8);
  return Uint8List.fromList(img.encodeJpg(i));
}

void main() {
  group('telling a scribble from a sticker', () {
    test('only a labelled PNG is a scribble', () {
      final labelled = img.Image(width: 8, height: 8)
        ..textData = {scribbleMarkerKey: scribbleMarkerValue};
      final bytes = Uint8List.fromList(img.encodePng(labelled));
      expect(hasScribbleMarker(bytes), isTrue);
      expect(imageExtension(bytes), 'scribble.png');

      expect(hasScribbleMarker(_plainPng()), isFalse);
      expect(imageExtension(_plainPng()), 'png');
      expect(imageExtension(_jpg()), 'jpg');
    });

    test('a scribble is shown whole and large; stickers stay small', () {
      expect(isScribble('/x/1.scribble.png'), isTrue);
      expect(isSmallMedia('/x/1.scribble.png'), isFalse);
      expect(isSmallMedia('/x/1.png'), isTrue);
      expect(isScribble('/x/1.png'), isFalse);
    });
  });

  testWidgets('a drawing becomes a labelled square picture', (t) async {
    late Uint8List png;
    await t.runAsync(() async {
      png = await renderScribble(
        strokes: [
          Stroke(
            color: const Color(0xFF000000),
            width: 10,
            points: [const Offset(20, 50), const Offset(180, 50)],
          ),
        ],
        displayedWidth: 200,
        paper: scribblePapers[0],
        pixels: 400,
      );
    });
    expect(hasScribbleMarker(png), isTrue);
    final out = img.decodePng(png)!;
    expect((out.width, out.height), (400, 400));
    // Paper in the corner, ink on the line (200 px wide pad → 2x).
    final corner = out.getPixel(2, 390);
    expect(corner.r.toInt(), greaterThan(200));
    final ink = out.getPixel(200, 100); // (100,50) on screen
    expect(ink.r.toInt(), lessThan(60));
  });

  group('the pad', () {
    testWidgets('Send waits for a drawing; the pen follows the paper', (
      t,
    ) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: ScribblePage()));

      TextButton send() =>
          t.widget(find.byKey(const ValueKey('scribble-send')));
      expect(send().onPressed, isNull, reason: 'nothing drawn yet');

      await t.drag(
        find.byKey(const ValueKey('scribble-pad')),
        const Offset(80, 40),
      );
      await t.pump();
      expect(send().onPressed, isNotNull);

      // Dark paper: the black pen would vanish, so the pen turns white.
      await t.tap(find.byKey(const ValueKey('scribble-paper-1')));
      await t.pump();
      final white = t.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('draw-color-0')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (white.decoration as BoxDecoration).border!.top.color,
        Colors.white,
        reason: 'white pen is the selected one',
      );
    });
  });

  group('the eraser', () {
    testWidgets('rubs out ink and leaves the paper', (t) async {
      late Uint8List png;
      await t.runAsync(() async {
        png = await renderScribble(
          strokes: [
            Stroke(
              color: const Color(0xFF000000),
              width: 20,
              points: [const Offset(10, 50), const Offset(190, 50)],
            ),
            // Rubbed out again over the left half only.
            Stroke(
              color: const Color(0xFF000000),
              width: 40,
              erase: true,
              points: [const Offset(0, 50), const Offset(100, 50)],
            ),
          ],
          displayedWidth: 200,
          paper: scribblePapers[0],
          pixels: 200,
        );
      });
      final out = img.decodePng(png)!;
      final erased = out.getPixel(40, 50); // left half: ink was rubbed out
      final inked = out.getPixel(160, 50); // right half: still black
      expect(erased.r.toInt(), greaterThan(200), reason: 'back to paper');
      expect(inked.r.toInt(), lessThan(60), reason: 'untouched ink');
    });

    testWidgets('never rubs out the picture under a drawing', (t) async {
      late Uint8List out;
      await t.runAsync(() async {
        final base = img.Image(width: 100, height: 100);
        img.fill(base, color: img.ColorRgb8(0, 0, 255));
        final codec = await ui.instantiateImageCodec(
          Uint8List.fromList(img.encodePng(base)),
        );
        final image = (await codec.getNextFrame()).image;
        out = await flattenStrokes(image, [
          Stroke(
            color: const Color(0xFFFF0000),
            width: 20,
            points: [const Offset(0, 50), const Offset(100, 50)],
          ),
          Stroke(
            color: const Color(0xFF000000),
            width: 60,
            erase: true,
            points: [const Offset(0, 50), const Offset(100, 50)],
          ),
        ], displayedWidth: 100);
      });
      final p = img.decodePng(out)!.getPixel(50, 50);
      // The red is gone and the BLUE picture is still there (not see-through).
      expect((p.r.toInt(), p.b.toInt()), (0, 255));
      expect(p.a.toInt(), 255);
    });

    testWidgets('the pad: eraser toggles, and a colour goes back to the pen', (
      t,
    ) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: ScribblePage()));

      Border borderOf(String key) =>
          ((t.widget<Container>(
                        find
                            .descendant(
                              of: find.byKey(ValueKey(key)),
                              matching: find.byType(Container),
                            )
                            .first,
                      )).decoration!
                      as BoxDecoration)
                  .border!
              as Border;

      expect(borderOf('draw-eraser').top.color, Colors.white24);
      await t.tap(find.byKey(const ValueKey('draw-eraser')));
      await t.pump();
      expect(borderOf('draw-eraser').top.color, Colors.white, reason: 'on');

      await t.tap(find.byKey(const ValueKey('draw-color-4')));
      await t.pump();
      expect(borderOf('draw-eraser').top.color, Colors.white24, reason: 'off');
    });
  });

  testWidgets('the eraser has its own three sizes, kept apart from the pen', (
    t,
  ) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: ScribblePage()));

    // The pen: its sizes, no eraser sizes.
    expect(find.byKey(const ValueKey('draw-size-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('draw-eraser-size-0')), findsNothing);

    // The eraser: its sizes take the pen sizes' place.
    await t.tap(find.byKey(const ValueKey('draw-eraser')));
    await t.pump();
    for (var i = 0; i < eraserWidths.length; i++) {
      expect(find.byKey(ValueKey('draw-eraser-size-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('draw-size-0')), findsNothing);
    await t.tap(find.byKey(const ValueKey('draw-eraser-size-2')));
    await t.pump();

    // Back to the pen and to the eraser again: each kept its own size.
    await t.tap(find.byKey(const ValueKey('draw-eraser')));
    await t.pump();
    expect(find.byKey(const ValueKey('draw-size-1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('draw-eraser')));
    await t.pump();
    final big = t.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('draw-eraser-size-2')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      ((big.decoration! as BoxDecoration).border! as Border).top.color,
      Colors.white,
      reason: 'the large eraser is still the chosen one',
    );
  });

  test('eraser sizes are bigger than the pens and grow', () {
    expect(strokeWidthFor(0, erase: false), drawWidths[0]);
    expect(strokeWidthFor(2, erase: true), eraserWidths[2]);
    for (var i = 0; i < eraserWidths.length; i++) {
      expect(eraserWidths[i], greaterThan(drawWidths[i]));
      if (i > 0) expect(eraserWidths[i], greaterThan(eraserWidths[i - 1]));
    }
  });

  testWidgets('the pad\'s tools fit a narrow phone, erasing too', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: ScribblePage()));
    await t.pump();
    expect(find.byKey(const ValueKey('draw-eraser')), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'no overflow at 320 px');
    await t.tap(find.byKey(const ValueKey('draw-eraser')));
    await t.pump();
    expect(find.byKey(const ValueKey('draw-eraser-size-2')), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'eraser sizes fit too');
  });
}
