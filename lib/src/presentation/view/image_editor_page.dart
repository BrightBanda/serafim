import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/utils/image_editor/draw_canvas.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Opens the editor on [bytes]. Returns the edited picture, or null if the
/// person backed out.
Future<Uint8List?> editImage(
  BuildContext context,
  Uint8List bytes, {
  int maxSide = 1280,
  int quality = 75,
}) => Navigator.of(context).push<Uint8List>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        ImageEditorPage(bytes: bytes, maxSide: maxSide, quality: quality),
  ),
);

enum _Mode { crop, draw }

/// Crop and draw on a picture before it is sent.
///
/// Drawing is applied to the picture before cropping: switching from Draw to
/// Crop bakes the lines in first, so a crop can never slide them out of place.
class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage({
    super.key,
    required this.bytes,
    this.maxSide = 1280,
    this.quality = 75,
  });

  final Uint8List bytes;
  final int maxSide;
  final int quality;

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  late Uint8List _base = widget.bytes;
  ui.Image? _decoded;
  _Mode _mode = _Mode.crop;
  bool _busy = false;
  bool _edited = false;

  final _cropController = CropController();
  double? _aspect;

  final List<Stroke> _strokes = [];
  int _color = defaultColorIndex;
  int _width = defaultWidthIndex;

  /// Width of the picture on screen while drawing (for the export scale).
  double _displayedWidth = 1;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(_base);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _decoded?.dispose();
      _decoded = frame.image;
    });
  }

  Future<void> _setMode(_Mode mode) async {
    if (mode == _mode || _busy) return;
    if (_mode == _Mode.draw && _strokes.isNotEmpty) await _bakeStrokes();
    if (mounted) setState(() => _mode = mode);
  }

  /// Draws the lines into the picture itself and starts a clean slate.
  Future<void> _bakeStrokes() async {
    final image = _decoded;
    if (image == null) return;
    setState(() => _busy = true);
    try {
      _base = await flattenStrokes(
        image,
        _strokes,
        displayedWidth: _displayedWidth,
      );
      _strokes.clear();
      await _decode();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _base = await compute(_rotate90, _base);
      _edited = true;
      _cropController.image = _base;
      await _decode();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    if (_busy) return;
    if (_mode == _Mode.crop) {
      setState(() => _busy = true);
      _cropController.crop(); // continues in _onCropped
      return;
    }
    setState(() => _busy = true);
    try {
      if (_strokes.isNotEmpty) await _bakeStrokes();
      await _finish(_base);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        await _finish(croppedImage);
      case CropFailure():
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Couldn't crop that.")));
        }
    }
  }

  /// Shrinks to the chat's photo quality, so an edited picture is no bigger
  /// than an unedited one.
  Future<void> _finish(Uint8List bytes) async {
    final out = await shrinkImage(
      bytes,
      maxSide: widget.maxSide,
      quality: widget.quality,
    );
    if (mounted) Navigator.of(context).pop(out);
  }

  Future<void> _cancel() async {
    final dirty = _edited || _strokes.isNotEmpty;
    if (!dirty) return Navigator.of(context).pop();
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Discard changes?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
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
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : _cancel,
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : _done,
              child: Text(
                'DONE',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _busy ? Colors.white38 : Colors.white,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _mode == _Mode.crop ? _cropArea() : _drawArea(),
                    ),
                    if (_busy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black38,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
              _toolbar(),
              _modeBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cropArea() {
    return Crop(
      key: ValueKey(_base),
      image: _base,
      controller: _cropController,
      aspectRatio: _aspect,
      baseColor: Colors.black,
      maskColor: Colors.black54,
      onCropped: _onCropped,
      onStatusChanged: (_) {},
    );
  }

  Widget _drawArea() {
    final image = _decoded;
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, box) {
        final aspect = image.width / image.height;
        var w = box.maxWidth;
        var h = w / aspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * aspect;
        }
        _displayedWidth = w;
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: GestureDetector(
              onPanStart: (d) => setState(() {
                _edited = true;
                _strokes.add(
                  Stroke(
                    color: drawColors[_color],
                    width: drawWidths[_width],
                    points: [d.localPosition],
                  ),
                );
              }),
              onPanUpdate: (d) =>
                  setState(() => _strokes.last.points.add(d.localPosition)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RawImage(image: image, fit: BoxFit.fill),
                  CustomPaint(painter: StrokePainter(strokes: _strokes)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _toolbar() {
    if (_mode == _Mode.crop) {
      Widget chip(String label, double? ratio) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _aspect == ratio,
          onSelected: (_) {
            setState(() => _aspect = ratio);
            _cropController.aspectRatio = ratio;
          },
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            chip('Free', null),
            chip('1:1', 1),
            chip('4:3', 4 / 3),
            chip('16:9', 16 / 9),
            const Spacer(),
            IconButton(
              tooltip: 'Rotate',
              icon: const Icon(Icons.rotate_90_degrees_cw, color: Colors.white),
              onPressed: _busy ? null : _rotate,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < drawColors.length; i++)
                GestureDetector(
                  key: ValueKey('draw-color-$i'),
                  onTap: () => setState(() => _color = i),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: drawColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: i == _color ? Colors.white : Colors.white24,
                        width: i == _color ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < drawWidths.length; i++)
                GestureDetector(
                  key: ValueKey('draw-size-$i'),
                  onTap: () => setState(() => _width = i),
                  child: Container(
                    width: 44,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: i == _width ? Colors.white : Colors.white24,
                        width: i == _width ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 8 + i * 6.0,
                      height: 8 + i * 6.0,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                key: const ValueKey('draw-undo'),
                tooltip: 'Undo',
                icon: const Icon(Icons.undo, color: Colors.white),
                onPressed: _strokes.isEmpty
                    ? null
                    : () => setState(() => _strokes.removeLast()),
              ),
              IconButton(
                key: const ValueKey('draw-clear'),
                tooltip: 'Clear all',
                icon: const Icon(Icons.delete_sweep, color: Colors.white),
                onPressed: _strokes.isEmpty
                    ? null
                    : () => setState(_strokes.clear),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeBar() {
    Widget tab(_Mode m, IconData icon, String label) => Expanded(
      child: InkWell(
        onTap: () => _setMode(m),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          color: _mode == m ? AppColors.primary : Colors.transparent,
          child: Column(
            children: [
              Icon(icon, color: Colors.white),
              Text(label, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        tab(_Mode.crop, Icons.crop, 'Crop'),
        tab(_Mode.draw, Icons.brush, 'Draw'),
      ],
    );
  }
}

Uint8List _rotate90(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  return Uint8List.fromList(img.encodePng(img.copyRotate(decoded, angle: 90)));
}
