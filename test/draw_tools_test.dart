import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/view/scribble_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/draw_together_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/chat/chat_image_gallery.dart';
import 'package:serafim/src/utils/image_editor/draw_pad.dart';
import 'package:serafim/src/utils/image_editor/scribble.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';

class _Ws extends WebSocketService {
  final sent = <Map<String, dynamic>>[];
  @override
  bool sendMessage(Map<String, dynamic> payload) {
    sent.add(payload);
    return true;
  }

  List<Map<String, dynamic>> get strokes => [
    for (final f in sent)
      if (f['op'] == 'stroke') f,
  ];
}

({_Ws ws, DrawTogether n, ProviderContainer c}) live() {
  final ws = _Ws();
  final c = ProviderContainer(
    overrides: [
      currentAccountIdProvider.overrideWithValue('me'),
      webSocketServiceProvider.overrideWithValue(ws),
    ],
  );
  addTearDown(c.dispose);
  final n = c.read(drawTogetherProvider.notifier);
  n.invite('ann');
  n.heard({'op': 'invited', 'session': 'S', 'peer_id': 'ann'});
  n.heard({'op': 'started', 'session': 'S', 'peer_id': 'ann', 'strokes': []});
  ws.sent.clear();
  return (ws: ws, n: n, c: c);
}

void line(DrawTogether n, {Brush brush = Brush.pen, int points = 2}) {
  n.beginStroke(
    color: const Color(0xFF000000),
    widthIndex: 0,
    erase: false,
    brush: brush,
    point: Offset.zero,
  );
  for (var i = 1; i < points; i++) {
    n.extendStroke(Offset(i / points, 0));
  }
  n.endStroke();
}

/// A pad with a record of what it reports.
class _Pad {
  final begun = <Offset>[];
  final extended = <Offset>[];
  int ended = 0;
  int cancelled = 0;

  Widget build({DrawSmoothing smoothing = DrawSmoothing.off}) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: DrawPad(
        padKey: const ValueKey('pad'),
        side: 200,
        paper: Colors.white,
        strokes: const [],
        smoothing: smoothing,
        onBegin: begun.add,
        onExtend: extended.add,
        onEnd: () => ended++,
        onCancel: () => cancelled++,
      ),
    ),
  );
}

void main() {
  group('redo', () {
    test('brings back my own line, for both phones, however long it is', () {
      final t = live();
      line(t.n, points: 500);
      final before = t.c.read(drawTogetherProvider)!.strokes.single;
      t.n.undo();
      expect(t.c.read(drawTogetherProvider)!.strokes, isEmpty);
      expect(t.n.canRedo, isTrue);
      t.ws.sent.clear();

      t.n.redo();
      expect(t.c.read(drawTogetherProvider)!.strokes.single, before);
      expect(t.n.canRedo, isFalse);
      // In frames the server accepts, the same id, ending with done.
      final frames = t.ws.strokes;
      expect(frames.length, greaterThan(1));
      for (final f in frames) {
        expect(
          (f['p'] as List).length,
          lessThanOrEqualTo(DrawTogether.maxNumbersPerFrame),
        );
      }
      expect(frames.map((f) => f['id']).toSet(), hasLength(1));
      expect(frames.last['done'], isTrue);
      expect(frames.first['done'], isFalse);
      final sent = [for (final f in frames) ...(f['p'] as List)];
      expect(sent.length, 1000);
    });

    test('a new line, or a cleared sheet, ends what can be redone', () {
      final t = live();
      line(t.n);
      t.n.undo();
      line(t.n);
      expect(t.n.canRedo, isFalse);
      t.n.undo();
      expect(t.n.canRedo, isTrue);
      t.n.heard({'op': 'clear', 'session': 'S'});
      expect(t.n.canRedo, isFalse);
    });

    test('never touches what my friend drew', () {
      final t = live();
      t.n.heard({
        'op': 'stroke',
        'session': 'S',
        'id': 'x',
        'c': 0xFF000000,
        'w': 0.02,
        'p': [0.1, 0.1],
      });
      t.n.undo(); // nothing of mine
      expect(t.n.canRedo, isFalse);
      expect(t.c.read(drawTogetherProvider)!.strokes, hasLength(1));
    });
  });

  group('auto smooth', () {
    test('off follows the finger; stronger irons out more wobble', () {
      Offset after(DrawSmoothing s) {
        final smoother = StrokeSmoother(s, Offset.zero);
        late Offset p;
        for (final y in [10.0, -10.0, 10.0, -10.0]) {
          p = smoother.follow(Offset(0, y));
        }
        return p;
      }

      expect(after(DrawSmoothing.off).dy, -10);
      expect(after(DrawSmoothing.light).dy.abs(), lessThan(10));
      expect(
        after(DrawSmoothing.strong).dy.abs(),
        lessThan(after(DrawSmoothing.light).dy.abs()),
      );
    });

    testWidgets('the line still ends where the finger stopped', (t) async {
      final pad = _Pad();
      await t.pumpWidget(pad.build(smoothing: DrawSmoothing.strong));
      final g = await t.startGesture(const Offset(20, 20));
      await g.moveTo(const Offset(100, 100));
      await g.up();
      expect(pad.begun.single, const Offset(0.1, 0.1));
      expect(pad.extended.first.dx, lessThan(0.5), reason: 'lags behind');
      expect(pad.extended.last, const Offset(0.5, 0.5));
      expect(pad.ended, 1);
    });
  });

  group('touch on the pad', () {
    testWidgets('a tap is a dot', (t) async {
      final pad = _Pad();
      await t.pumpWidget(pad.build());
      await t.tapAt(const Offset(40, 60));
      expect(pad.begun.single, const Offset(0.2, 0.3));
      expect(pad.extended, isEmpty);
      expect(pad.ended, 1);
    });

    testWidgets('two fingers zoom and pan, and leave no mark', (t) async {
      final pad = _Pad();
      await t.pumpWidget(pad.build());
      final a = await t.startGesture(const Offset(80, 100), pointer: 1);
      final b = await t.startGesture(const Offset(120, 100), pointer: 2);
      await a.moveTo(const Offset(60, 100));
      await b.moveTo(const Offset(140, 100));
      await a.up();
      // The second finger lifting late must not start a line either.
      await b.moveTo(const Offset(140, 100));
      await b.up();
      await t.pump();
      expect(pad.begun, isEmpty);
      expect(pad.ended, 0);
      expect(find.text('2.0×'), findsOneWidget);

      // Zoomed in, one finger draws where the sheet now is: the middle of the
      // pad stays the middle of the sheet.
      await t.tapAt(const Offset(100, 100));
      expect(pad.begun.single.dx, closeTo(0.5, 0.05));

      // One tap puts it back.
      await t.tap(find.byKey(const ValueKey('draw-zoom-reset')));
      await t.pump();
      expect(find.byKey(const ValueKey('draw-zoom-reset')), findsNothing);
    });

    testWidgets('a pinch that begins as a line takes the line back', (t) async {
      final pad = _Pad();
      await t.pumpWidget(pad.build());
      final a = await t.startGesture(const Offset(80, 100), pointer: 1);
      await a.moveTo(const Offset(90, 100));
      expect(pad.begun, hasLength(1));
      final b = await t.startGesture(const Offset(120, 100), pointer: 2);
      expect(pad.cancelled, 1);
      await a.up();
      await b.up();
      expect(pad.ended, 0);
    });
  });

  group('brushes and stickers on the wire', () {
    test('a brush travels; a plain pen stays as it always was', () {
      final t = live();
      line(t.n, brush: Brush.marker);
      expect(t.ws.strokes.last['b'], 'marker');
      t.ws.sent.clear();
      line(t.n);
      expect(t.ws.strokes.last.containsKey('b'), isFalse);
    });

    test("a friend's brush and sticker arrive; unknown brushes are a pen", () {
      final t = live();
      void hear(String id, Map<String, dynamic> extra) => t.n.heard({
        'op': 'stroke',
        'session': 'S',
        'id': id,
        'c': 0,
        'w': 0.01,
        'p': [0.5, 0.5],
        ...extra,
      });
      hear('1', {'b': 'ink'});
      hear('2', {'b': 'from-the-future'});
      hear('3', {'s': 'doodles/frog', 'z': 0.4, 'r': 0.5});
      final s = t.c.read(drawTogetherProvider)!.strokes;
      expect(s[0].stroke.brush, Brush.ink);
      expect(s[1].stroke.brush, Brush.pen);
      expect(s[2].stroke.sticker, 'doodles/frog');
      expect(s[2].stroke.stickerSize, 0.4);
      expect(s[2].stroke.stickerRotation, 0.5);
    });

    test('a sticker undoes and redoes, and an old app sees nothing of it', () {
      final t = live();
      t.n.placeSticker(
        'doodles/jellyfish',
        at: const Offset(0.5, 0.5),
        size: 0.3,
        rotation: 0,
      );
      final frame = t.ws.strokes.single;
      expect(frame['s'], 'doodles/jellyfish');
      expect(frame['c'], 0, reason: 'a transparent dot to an older app');
      expect(frame['done'], isTrue);
      t.n.undo();
      t.ws.sent.clear();
      t.n.redo();
      expect(t.ws.strokes.single['s'], 'doodles/jellyfish');
    });

    test('a pinch that began as a line is taken back for the friend too', () {
      final t = live();
      t.n.beginStroke(
        color: const Color(0xFF000000),
        widthIndex: 0,
        erase: false,
        point: Offset.zero,
      );
      t.n.cancelStroke();
      expect(t.c.read(drawTogetherProvider)!.strokes, isEmpty);
      expect(t.n.canRedo, isFalse);
      expect(t.ws.sent.last['op'], 'undo');
    });
  });

  test('the jellyfish is in the Doodle Gang, without moving anyone else', () {
    final gang = stickerPacks.firstWhere((p) => p.id == 'doodles');
    expect(gang.name, 'Doodle Gang');
    expect(gang.stickers.map((s) => s.id), contains('doodles/jellyfish'));
    // Ids are what old messages refer to.
    expect(stickerById('doodles/frog'), isNotNull);
  });

  group('rendering', () {
    Future<img.Image> render(
      WidgetTester t,
      List<Stroke> strokes, {
      ui.Image? drawing,
    }) async {
      late Uint8List png;
      await t.runAsync(() async {
        png = await renderScribble(
          strokes: strokes,
          displayedWidth: 1,
          paper: const Color(0xFFFFFFFF),
          pixels: 200,
          drawing: drawing,
        );
      });
      return img.decodePng(png)!;
    }

    Stroke across(Brush brush) => Stroke(
      color: const Color(0xFF000000),
      width: 0.02,
      brush: brush,
      points: [for (var x = 0.1; x < 0.9; x += 0.05) Offset(x, 0.5)],
    );

    testWidgets('each brush leaves its own mark', (t) async {
      num darkness(img.Image i) => 255 - i.getPixel(100, 100).r;
      num thickness(img.Image i) {
        var n = 0;
        for (var y = 0; y < 200; y++) {
          if (i.getPixel(100, y).r < 250) n++;
        }
        return n;
      }

      final pen = await render(t, [across(Brush.pen)]);
      final marker = await render(t, [across(Brush.marker)]);
      final high = await render(t, [across(Brush.highlighter)]);
      final ink = await render(t, [across(Brush.ink)]);
      expect(darkness(pen), greaterThan(250));
      expect(thickness(marker), greaterThan(thickness(pen)));
      expect(thickness(high), greaterThan(thickness(marker)));
      expect(darkness(high), lessThan(darkness(marker)));
      expect(darkness(ink), greaterThan(200));
    });

    testWidgets('stickers are drawn on the sheet', (t) async {
      final out = await render(t, [
        Stroke.sticker(
          'doodles/jellyfish',
          at: const Offset(0.5, 0.5),
          size: 0.8,
        ),
      ]);
      // The sticker's navy edge is on its circle, not on the bare paper.
      expect(out.getPixel(5, 5).r, 255);
      var navy = 0;
      for (var x = 0; x < 200; x++) {
        if (out.getPixel(x, 100).r < 80) navy++;
      }
      expect(navy, greaterThan(0));
    });

    testWidgets('a sticker from a newer app is simply left out', (t) async {
      final out = await render(t, [
        Stroke.sticker('future/thing', at: const Offset(0.5, 0.5), size: 0.8),
      ]);
      expect(out.getPixel(100, 100).r, 255);
    });

    testWidgets('an edited copy keeps the drawing; the eraser can rub it out', (
      t,
    ) async {
      final original = img.Image(width: 50, height: 50)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.fillRect(
        original,
        x1: 0,
        y1: 20,
        x2: 49,
        y2: 30,
        color: img.ColorRgb8(0, 0, 0),
      );
      late ui.Image drawing;
      await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          Uint8List.fromList(img.encodePng(original)),
        );
        drawing = (await codec.getNextFrame()).image;
      });
      addTearDown(drawing.dispose);

      final kept = await render(t, const [], drawing: drawing);
      expect(kept.getPixel(100, 100).r, lessThan(20), reason: 'line is there');

      final rubbed = await render(t, [
        Stroke(
          color: const Color(0xFF000000),
          width: 0.3,
          erase: true,
          points: const [Offset(0.5, 0.5)],
        ),
      ], drawing: drawing);
      expect(rubbed.getPixel(100, 100).r, 255, reason: 'back to the paper');
      expect(
        rubbed.getPixel(10, 100).r,
        lessThan(20),
        reason: 'the rest stays',
      );
    });
  });

  group('editing a copy', () {
    late Directory dir;
    late String path;

    Future<void> makeDrawing(WidgetTester t, Color paper) async {
      await t.runAsync(() async {
        dir = Directory.systemTemp.createTempSync('edit');
        path = '${dir.path}/1.scribble.png';
        final png = await renderScribble(
          strokes: [
            Stroke(
              color: const Color(0xFFE53935),
              width: 0.05,
              points: const [Offset(0.2, 0.5), Offset(0.8, 0.5)],
            ),
          ],
          displayedWidth: 1,
          paper: paper,
          pixels: 100,
        );
        File(path).writeAsBytesSync(png);
      });
      addTearDown(() => dir.deleteSync(recursive: true));
    }

    testWidgets('opens the drawing, and sends a new picture back', (t) async {
      await makeDrawing(t, scribblePapers[1]);
      final before = File(path).readAsBytesSync();
      Uint8List? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await scribble(context, editing: path),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      // Decoding happens off the test's clock: take turns until it is done.
      final pad = find.byKey(const ValueKey('scribble-pad'));
      for (var i = 0; i < 50 && pad.evaluate().isEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Edit a copy'), findsOneWidget);
      expect(find.byKey(const ValueKey('scribble-copy-note')), findsOneWidget);
      // It keeps its paper: there is nothing to pick.
      expect(find.byKey(const ValueKey('scribble-paper-0')), findsNothing);

      TextButton send() =>
          t.widget(find.byKey(const ValueKey('scribble-send')));
      expect(send().onPressed, isNull, reason: 'nothing changed yet');
      await t.drag(
        find.byKey(const ValueKey('scribble-pad')),
        const Offset(60, 30),
      );
      await t.pump();
      expect(send().onPressed, isNotNull);

      await t.tap(find.byKey(const ValueKey('scribble-send')));
      for (var i = 0; i < 50 && result == null; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(result, isNotNull);
      expect(hasScribbleMarker(result!), isTrue);
      expect(File(path).readAsBytesSync(), before, reason: 'original intact');
    });

    testWidgets('the paper is read from the drawing', (t) async {
      await makeDrawing(t, scribblePapers[2]);
      Color? paper;
      await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          File(path).readAsBytesSync(),
        );
        final image = (await codec.getNextFrame()).image;
        paper = await paperOf(image);
        image.dispose();
      });
      expect(paper!.toARGB32(), scribblePapers[2].toARGB32());
    });

    testWidgets('the viewer offers it only when given, and returns to the '
        'chat once sent', (t) async {
      await makeDrawing(t, scribblePapers[0]);
      var edits = 0;
      Future<void> open({Future<bool> Function()? onEdit}) async {
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openChatImageGallery(context, [
                  (path: path, onSave: null, onDelete: null, onEdit: onEdit),
                ]),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await t.tap(find.text('open'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      }

      await open();
      expect(find.byKey(const ValueKey('gallery-edit-copy')), findsNothing);

      await open(
        onEdit: () async {
          edits++;
          return edits > 1;
        },
      );
      await t.tap(find.byKey(const ValueKey('gallery-edit-copy')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('gallery-edit-copy')),
        findsOneWidget,
        reason: 'backed out: stays',
      );
      await t.tap(find.byKey(const ValueKey('gallery-edit-copy')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gallery-edit-copy')),
        findsNothing,
        reason: 'sent: back to the chat',
      );
    });
  });

  testWidgets('the sticker picker offers the gang, and placing works', (
    t,
  ) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: ScribblePage()));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('draw-stickers')));
    await t.pumpAndSettle();
    final jelly = find.byKey(const ValueKey('draw-sticker-doodles/jellyfish'));
    await t.ensureVisible(jelly);
    await t.pumpAndSettle();
    await t.tap(jelly);
    await t.pumpAndSettle();

    // Nothing is on the sheet until it is placed.
    TextButton send() => t.widget(find.byKey(const ValueKey('scribble-send')));
    expect(send().onPressed, isNull);
    await t.drag(
      find.byKey(const ValueKey('scribble-pad')),
      const Offset(40, 40),
    );
    await t.pump();
    expect(
      send().onPressed,
      isNull,
      reason: 'dragging moves it, draws nothing',
    );
    await t.tap(find.byKey(const ValueKey('sticker-place')));
    await t.pump();
    expect(send().onPressed, isNotNull);
    expect(find.byKey(const ValueKey('sticker-place')), findsNothing);

    await t.tap(find.byKey(const ValueKey('draw-undo')));
    await t.pump();
    expect(send().onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('draw-redo')));
    await t.pump();
    expect(send().onPressed, isNotNull);
  });

  testWidgets('smoothing is a tap away, and cycles', (t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: ScribblePage()));
    await t.pump();
    expect(find.text('Smooth\nLight'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('draw-smoothing')));
    await t.pump();
    expect(find.text('Smooth\nStrong'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('draw-smoothing')));
    await t.pump();
    expect(find.text('Smooth\nOff'), findsOneWidget);
  });
}
