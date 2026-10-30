import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/presentation/view/image_editor_page.dart';
import 'package:serafim/src/presentation/view/image_preview_page.dart';

Uint8List _png() {
  final image = img.Image(width: 120, height: 80);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));
  return Uint8List.fromList(img.encodePng(image));
}

/// Opens the preview from a button and reports what it returned.
Future<ValueNotifier<Object?>> _open(WidgetTester t, Uint8List bytes) async {
  final result = ValueNotifier<Object?>('not closed');
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                result.value = await previewImage(context, bytes),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return result;
}

Future<ValueNotifier<Object?>> _openBatch(
  WidgetTester t,
  List<Uint8List> photos,
) async {
  final result = ValueNotifier<Object?>('not closed');
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                result.value = await previewImages(context, photos),
            child: const Text('open batch'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open batch'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('a picture is only previewed: Send returns it as it was', (
    t,
  ) async {
    final bytes = _png();
    final result = await _open(t, bytes);

    expect(find.byKey(const ValueKey('preview-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-edit')), findsOneWidget);
    expect(find.byType(ImageEditorPage), findsNothing, reason: 'no editor yet');

    await t.tap(find.byKey(const ValueKey('preview-send')));
    await t.pumpAndSettle();
    expect(result.value, same(bytes), reason: 'sent untouched');
  });

  testWidgets('closing the preview sends nothing', (t) async {
    final result = await _open(t, _png());
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(result.value, isNull);
  });

  testWidgets(
    'batch preview opens each tile independently and sends originals',
    (t) async {
      final photos = [_png(), _png(), _png(), _png()];
      final result = await _openBatch(t, photos);

      expect(find.byType(GridView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('batch-preview-tile-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch-preview-tile-3')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('batch-preview-send')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('batch-preview-tile-0')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('batch-preview-fullscreen-0')),
        findsOneWidget,
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('batch-preview-send')));
      await t.pumpAndSettle();
      expect(result.value, same(photos));
    },
  );

  testWidgets('Edit opens the editor, and backing out keeps the picture', (
    t,
  ) async {
    final bytes = _png();
    final result = await _open(t, bytes);

    await t.tap(find.byKey(const ValueKey('preview-edit')));
    await t.pumpAndSettle();
    expect(find.byType(ImageEditorPage), findsOneWidget);

    await t.tap(find.byIcon(Icons.close)); // nothing changed: leaves at once
    await t.pumpAndSettle();
    expect(find.byType(ImageEditorPage), findsNothing);
    expect(find.byKey(const ValueKey('preview-send')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('preview-send')));
    await t.pumpAndSettle();
    expect(result.value, same(bytes));
  });

  testWidgets('the crop options fit a narrow phone without overflowing', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(home: ImageEditorPage(bytes: _png())));
    await t.pump(const Duration(milliseconds: 600));

    expect(find.text('16:9'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'no RenderFlex overflow');
  });
}
