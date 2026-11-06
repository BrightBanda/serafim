import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/utils/image_editor/draw_pad.dart';
import 'package:serafim/src/utils/image_editor/draw_toolbar.dart';
import 'package:serafim/src/utils/image_editor/scribble.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// Opens the scribble pad. Returns the drawing as a picture to send, or null
/// if the person backed out. With [editing] (the path of a scribble) the pad
/// starts from a copy of that drawing; the original stays as it is.
Future<Uint8List?> scribble(BuildContext context, {String? editing}) =>
    Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScribblePage(editing: editing),
      ),
    );

/// The paper an earlier drawing was made on: whichever colour most of its
/// corners agree on (a line may cross one corner, not all of them).
Future<Color> paperOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return scribblePapers.first;
  Color at(int x, int y) {
    final o = (y * image.width + x) * 4;
    return Color.fromARGB(
      data.getUint8(o + 3),
      data.getUint8(o),
      data.getUint8(o + 1),
      data.getUint8(o + 2),
    );
  }

  final w = image.width - 1, h = image.height - 1;
  final corners = [at(0, 0), at(w, 0), at(0, h), at(w, h)];
  final count = <Color, int>{};
  for (final c in corners) {
    count[c] = (count[c] ?? 0) + 1;
  }
  return corners.reduce((a, b) => count[b]! > count[a]! ? b : a);
}

/// A blank square to draw a quick note on and send: a hand-drawn whisper. Or,
/// with [editing], a copy of someone's drawing to change and send back.
class ScribblePage extends StatefulWidget {
  const ScribblePage({super.key, this.editing});

  /// The path of the drawing this starts from.
  final String? editing;

  @override
  State<ScribblePage> createState() => _ScribblePageState();
}

class _ScribblePageState extends State<ScribblePage> {
  final List<Stroke> _strokes = [];
  final List<Stroke> _undone = [];
  int _color = 1; // black on paper
  int _width = defaultWidthIndex;
  int _eraserWidth = defaultEraserIndex;
  bool _erasing = false;
  int _paper = 0;
  bool _busy = false;
  Brush _brush = Brush.pen;
  DrawSmoothing _smoothing = DrawSmoothing.light;
  String? _placing;

  /// The drawing being edited, once it has loaded, and the paper it is on.
  ui.Image? _drawing;
  Color? _editedPaper;

  bool get _editing => widget.editing != null;
  Color get _sheet => _editedPaper ?? scribblePapers[_paper];

  @override
  void initState() {
    super.initState();
    loadDrawSmoothing().then((s) {
      if (mounted) setState(() => _smoothing = s);
    });
    if (_editing) _loadDrawing();
  }

  Future<void> _loadDrawing() async {
    try {
      final bytes = await File(widget.editing!).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final paper = await paperOf(image);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _drawing = image;
        _editedPaper = paper;
        if (paper.computeLuminance() < 0.2) _color = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanError(e, fallback: "Couldn't open that drawing.")),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _drawing?.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _strokes.isEmpty) return;
    setState(() => _busy = true);
    try {
      final png = await renderScribble(
        strokes: _strokes,
        // The strokes are fractions of the sheet, so "1 wide" scales them.
        displayedWidth: 1,
        paper: _sheet,
        drawing: _drawing,
      );
      if (mounted) Navigator.of(context).pop(png);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Picking the dark paper while the pen is black (or the reverse) would
  /// draw invisible lines, so the pen follows to white / black.
  void _choosePaper(int i) {
    setState(() {
      _paper = i;
      final dark = scribblePapers[i].computeLuminance() < 0.2;
      if (dark && _color == 1) _color = 0;
      if (!dark && _color == 0) _color = 1;
    });
  }

  void _add(Stroke stroke) => setState(() {
    _undone.clear();
    _strokes.add(stroke);
  });

  Future<void> _pickSticker() async {
    final id = await pickDrawSticker(context);
    if (id != null && mounted) setState(() => _placing = id);
  }

  Future<void> _cancel() async {
    if (_strokes.isEmpty) return Navigator.of(context).pop();
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          _editing ? 'Throw this copy away?' : 'Throw this scribble away?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep drawing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Throw away'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final loading = _editing && _drawing == null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_editing ? 'Edit a copy' : 'Scribble'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : _cancel,
          ),
          actions: [
            TextButton(
              key: const ValueKey('scribble-send'),
              onPressed: _busy || _strokes.isEmpty ? null : _send,
              child: Text(
                'SEND',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _busy || _strokes.isEmpty
                      ? Colors.white38
                      : Colors.white,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Goes out as a new copy. The original stays as it is.',
                    key: const ValueKey('scribble-copy-note'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // The biggest square that fits, inset from the edges so
                    // a phone's back-swipe gesture is not under the pen.
                    final side =
                        (box.maxWidth < box.maxHeight
                            ? box.maxWidth
                            : box.maxHeight) -
                        32;
                    if (loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Center(
                      child: DrawPad(
                        padKey: const ValueKey('scribble-pad'),
                        side: side,
                        paper: _sheet,
                        drawing: _drawing,
                        smoothing: _smoothing,
                        strokes: _strokes,
                        onBegin: (point) => _add(
                          Stroke(
                            color: drawColors[_color],
                            width:
                                strokeWidthFor(
                                  _erasing ? _eraserWidth : _width,
                                  erase: _erasing,
                                ) /
                                referencePadWidth,
                            erase: _erasing,
                            brush: _brush,
                            points: [point],
                          ),
                        ),
                        onExtend: (point) =>
                            setState(() => _strokes.last.points.add(point)),
                        onEnd: () {},
                        onCancel: () => setState(_strokes.removeLast),
                        placing: _placing,
                        onPlacingCancelled: () =>
                            setState(() => _placing = null),
                        onPlaced: (at, size, rotation) {
                          _add(
                            Stroke.sticker(
                              _placing!,
                              at: at,
                              size: size,
                              rotation: rotation,
                            ),
                          );
                          setState(() => _placing = null);
                        },
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: DrawToolbar(
                  color: _color,
                  width: _width,
                  onColor: (i) => setState(() {
                    _color = i;
                    _erasing = false;
                  }),
                  onWidth: (i) => setState(() => _width = i),
                  eraserWidth: _eraserWidth,
                  onEraserWidth: (i) => setState(() => _eraserWidth = i),
                  erasing: _erasing,
                  onEraser: () => setState(() => _erasing = !_erasing),
                  hasStrokes: _strokes.isNotEmpty,
                  onUndo: () =>
                      setState(() => _undone.add(_strokes.removeLast())),
                  canRedo: _undone.isNotEmpty,
                  onRedo: () =>
                      setState(() => _strokes.add(_undone.removeLast())),
                  onClear: () => setState(() {
                    _strokes.clear();
                    _undone.clear();
                  }),
                  brush: _brush,
                  onBrush: (b) => setState(() {
                    _brush = b;
                    _erasing = false;
                  }),
                  smoothing: _smoothing,
                  onSmoothing: (next) {
                    saveDrawSmoothing(next);
                    setState(() => _smoothing = next);
                  },
                  onSticker: _pickSticker,
                  // An edited drawing keeps the paper it was drawn on.
                  extra: _editing
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < scribblePapers.length; i++)
                              GestureDetector(
                                key: ValueKey('scribble-paper-$i'),
                                onTap: () => _choosePaper(i),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    color: scribblePapers[i],
                                    border: Border.all(
                                      color: i == _paper
                                          ? Colors.white
                                          : Colors.white24,
                                      width: i == _paper ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
