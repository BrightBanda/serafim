import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/image_editor/draw_canvas.dart';
import 'package:serafim/src/utils/image_editor/draw_toolbar.dart';
import 'package:serafim/src/utils/image_editor/scribble.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// Opens the scribble pad. Returns the drawing as a picture to send, or null
/// if the person backed out.
Future<Uint8List?> scribble(BuildContext context) =>
    Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ScribblePage(),
      ),
    );

/// A blank square to draw a quick note on and send: a hand-drawn whisper.
class ScribblePage extends StatefulWidget {
  const ScribblePage({super.key});

  @override
  State<ScribblePage> createState() => _ScribblePageState();
}

class _ScribblePageState extends State<ScribblePage> {
  final List<Stroke> _strokes = [];
  int _color = 1; // black on paper
  int _width = defaultWidthIndex;
  bool _erasing = false;
  int _paper = 0;
  double _padWidth = 1;
  bool _busy = false;

  Future<void> _send() async {
    if (_busy || _strokes.isEmpty) return;
    setState(() => _busy = true);
    try {
      final png = await renderScribble(
        strokes: _strokes,
        displayedWidth: _padWidth,
        paper: scribblePapers[_paper],
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

  Future<void> _cancel() async {
    if (_strokes.isEmpty) return Navigator.of(context).pop();
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: const Text('Throw this scribble away?'),
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
          title: const Text('Scribble'),
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
                    _padWidth = side;
                    return Center(
                      child: Container(
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          color: scribblePapers[_paper],
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                        child: GestureDetector(
                          key: const ValueKey('scribble-pad'),
                          onPanStart: (d) => setState(
                            () => _strokes.add(
                              Stroke(
                                color: drawColors[_color],
                                width:
                                    drawWidths[_width] *
                                    (_erasing ? eraserWidthFactor : 1),
                                erase: _erasing,
                                points: [d.localPosition],
                              ),
                            ),
                          ),
                          onPanUpdate: (d) => setState(
                            () => _strokes.last.points.add(d.localPosition),
                          ),
                          child: CustomPaint(
                            painter: StrokePainter(strokes: _strokes),
                            size: Size.infinite,
                          ),
                        ),
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
                  erasing: _erasing,
                  onEraser: () => setState(() => _erasing = !_erasing),
                  hasStrokes: _strokes.isNotEmpty,
                  onUndo: () => setState(() => _strokes.removeLast()),
                  onClear: () => setState(_strokes.clear),
                  extra: Row(
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
