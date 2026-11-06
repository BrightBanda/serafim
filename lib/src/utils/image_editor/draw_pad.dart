import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/image_editor/draw_canvas.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/stickers/sticker_view.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sheet behind Draw Together and the scribble pad.
///
/// One finger draws (a tap makes a dot); two fingers zoom and move the sheet.
/// Everything it reports is in sheet widths (see [drawSheetAspect]), whatever
/// the zoom or the size of the screen. It holds no drawing of its own: the screen
/// keeps the strokes and passes them back in.
class DrawPad extends StatefulWidget {
  const DrawPad({
    super.key,
    required this.padKey,
    required this.side,
    this.aspect = 1,
    required this.paper,
    required this.strokes,
    required this.onBegin,
    required this.onExtend,
    required this.onEnd,
    required this.onCancel,
    this.smoothing = DrawSmoothing.off,
    this.enabled = true,
    this.drawing,
    this.placing,
    this.onPlaced,
    this.onPlacingCancelled,
    this.overlay = const [],
  });

  /// On the part that takes touches.
  final Key padKey;

  /// How wide it is on screen, and how many times that it is tall.
  final double side;
  final double aspect;
  final Color paper;
  final List<Stroke> strokes;
  final ValueChanged<Offset> onBegin;
  final ValueChanged<Offset> onExtend;
  final VoidCallback onEnd;

  /// The line just begun was the first finger of a pinch, not a line.
  final VoidCallback onCancel;
  final DrawSmoothing smoothing;

  /// False: the sheet can still be looked around, but not drawn on.
  final bool enabled;

  /// An earlier drawing being edited (see [StrokePainter.drawing]).
  final ui.Image? drawing;

  /// The id of a sticker being positioned: while set, fingers move, size and
  /// turn it instead of drawing.
  final String? placing;
  final void Function(Offset at, double size, double rotation)? onPlaced;
  final VoidCallback? onPlacingCancelled;

  /// More on top of the sheet, not zoomed with it (e.g. a notice).
  final List<Widget> overlay;

  /// Starting size of a sticker, as a fraction of the sheet.
  static const stickerStartSize = 0.3;
  static const maxZoom = 6.0;

  @override
  State<DrawPad> createState() => _DrawPadState();
}

class _DrawPadState extends State<DrawPad> {
  /// A line this young when a second finger lands was a pinch starting.
  static const _pinchWithin = Duration(milliseconds: 300);

  final _fingers = <int, Offset>{};
  final _clock = Stopwatch();

  // On screen, a point of the sheet is at `point * _zoom + _pan`.
  double _zoom = 1;
  Offset _pan = Offset.zero;

  // This touch.
  bool _pinching = false;
  bool _drawing = false;
  Offset _downAt = Offset.zero;
  Offset _last = Offset.zero;
  StrokeSmoother? _smoother;

  // The pinch, as it was when it started.
  double _pinchSpread = 1;
  double _pinchAngle = 0;
  Offset _pinchCentre = Offset.zero;
  double _zoomAtStart = 1;
  Offset _panAtStart = Offset.zero;

  // The sticker being placed.
  Offset _stickerAt = const Offset(0.5, 0.5);
  double _stickerSize = DrawPad.stickerStartSize;
  double _stickerTurn = 0;
  double _sizeAtStart = 1;
  double _turnAtStart = 0;

  @override
  void didUpdateWidget(DrawPad old) {
    super.didUpdateWidget(old);
    if (widget.placing != null && widget.placing != old.placing) {
      // In the middle of what is on screen right now.
      _stickerAt = _toSheet(Offset(widget.side, _tall) / 2);
      _stickerSize = DrawPad.stickerStartSize / _zoom;
      _stickerTurn = 0;
    }
  }

  Offset _toSheet(Offset onScreen) {
    return _clampToSheet((onScreen - _pan) / (_zoom * widget.side));
  }

  void _down(PointerDownEvent e) {
    _fingers[e.pointer] = e.localPosition;
    if (_fingers.length == 1) {
      _pinching = false;
      _drawing = false;
      _downAt = _last = e.localPosition;
      _clock
        ..reset()
        ..start();
    } else if (_fingers.length == 2) {
      if (_drawing) {
        _clock.elapsed < _pinchWithin ? widget.onCancel() : widget.onEnd();
        _drawing = false;
      }
      _pinching = true;
      final (a, b) = _pair();
      _pinchSpread = math.max((a - b).distance, 1);
      _pinchAngle = (b - a).direction;
      _pinchCentre = (a + b) / 2;
      _zoomAtStart = _zoom;
      _panAtStart = _pan;
      _sizeAtStart = _stickerSize;
      _turnAtStart = _stickerTurn;
    }
  }

  (Offset, Offset) _pair() {
    final held = _fingers.values.iterator..moveNext();
    final a = held.current;
    held.moveNext();
    return (a, held.current);
  }

  void _move(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.localPosition;
    if (_pinching) {
      if (_fingers.length >= 2) _pinchMoved();
      return;
    }
    if (widget.placing != null) {
      final delta = e.localPosition - _last;
      _last = e.localPosition;
      setState(
        () => _stickerAt = _clampToSheet(
          _stickerAt + delta / (_zoom * widget.side),
        ),
      );
      return;
    }
    if (!widget.enabled) {
      // Nothing to draw on: one finger looks around a zoomed sheet.
      final delta = e.localPosition - _last;
      _last = e.localPosition;
      setState(() => _pan = _clampPan(_pan + delta, _zoom));
      return;
    }
    if (!_drawing) {
      // Only a real movement starts a line; otherwise it may yet be a tap.
      if ((e.localPosition - _downAt).distance < 3) return;
      _start();
    }
    if ((e.localPosition - _last).distance < 1) return;
    _last = e.localPosition;
    widget.onExtend(_smoother!.follow(_toSheet(e.localPosition)));
  }

  void _start() {
    final at = _toSheet(_downAt);
    _smoother = StrokeSmoother(widget.smoothing, at);
    _drawing = true;
    widget.onBegin(at);
  }

  void _up(PointerEvent e, {required bool cancelled}) {
    if (_fingers.remove(e.pointer) == null || _fingers.isNotEmpty) return;
    final wasPinch = _pinching;
    _pinching = false;
    if (widget.placing != null || wasPinch || !widget.enabled) return;
    if (_drawing) {
      // The line catches up with where the finger actually stopped.
      widget.onExtend(_toSheet(e.localPosition));
      widget.onEnd();
    } else if (!cancelled) {
      _start();
      widget.onEnd();
    }
    _drawing = false;
  }

  void _pinchMoved() {
    final (a, b) = _pair();
    final ratio = (a - b).distance / _pinchSpread;
    if (widget.placing != null) {
      final turned = (b - a).direction - _pinchAngle;
      setState(() {
        _stickerSize = (_sizeAtStart * ratio).clamp(0.06, 1.0);
        _stickerTurn = _turnAtStart + turned;
      });
      return;
    }
    final zoom = (_zoomAtStart * ratio).clamp(1.0, DrawPad.maxZoom);
    final held = (_pinchCentre - _panAtStart) / _zoomAtStart;
    setState(() {
      _zoom = zoom;
      _pan = _clampPan((a + b) / 2 - held * zoom, zoom);
    });
  }

  Offset _clampToSheet(Offset p) =>
      Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, widget.aspect));

  double get _tall => widget.side * widget.aspect;

  /// The sheet always fills the pad: no empty space past its edges.
  Offset _clampPan(Offset pan, double zoom) {
    return Offset(
      pan.dx.clamp(widget.side * (1 - zoom), 0.0),
      pan.dy.clamp(_tall * (1 - zoom), 0.0),
    );
  }

  void _resetZoom() => setState(() {
    _zoom = 1;
    _pan = Offset.zero;
  });

  @override
  Widget build(BuildContext context) {
    final placing = widget.placing;
    final strokes = placing == null
        ? widget.strokes
        : [
            ...widget.strokes,
            Stroke.sticker(
              placing,
              at: _stickerAt,
              size: _stickerSize,
              rotation: _stickerTurn,
            ),
          ];
    return SizedBox(
      width: widget.side,
      height: _tall,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: widget.paper,
              // On top rather than around, so the sheet, and a finger's
              // position on it, is exactly [side] across.
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: Listener(
                key: widget.padKey,
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: (e) => _up(e, cancelled: false),
                onPointerCancel: (e) => _up(e, cancelled: true),
                child: ClipRect(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SheetPainter(
                        zoom: _zoom,
                        pan: _pan,
                        inner: StrokePainter(
                          strokes: strokes,
                          scale: widget.side,
                          drawing: widget.drawing,
                        ),
                        sheet: Size(widget.side, _tall),
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ...widget.overlay,
          if (_zoom > 1.01 && placing == null)
            Positioned(
              top: 8,
              right: 8,
              child: _PadChip(
                key: const ValueKey('draw-zoom-reset'),
                icon: Icons.zoom_out_map,
                label: '${_zoom.toStringAsFixed(1)}×',
                onTap: _resetZoom,
              ),
            ),
          if (placing != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PadChip(
                    key: const ValueKey('sticker-cancel'),
                    icon: Icons.close,
                    label: 'Cancel',
                    onTap: () => widget.onPlacingCancelled?.call(),
                  ),
                  const SizedBox(width: 8),
                  _PadChip(
                    key: const ValueKey('sticker-place'),
                    icon: Icons.check,
                    label: 'Place',
                    onTap: () => widget.onPlaced?.call(
                      _stickerAt,
                      _stickerSize,
                      _stickerTurn,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The sheet at its current zoom. Redrawn from the strokes rather than
/// stretched, so lines stay sharp however far you zoom in.
class _SheetPainter extends CustomPainter {
  _SheetPainter({
    required this.zoom,
    required this.pan,
    required this.inner,
    required this.sheet,
  });

  final double zoom;
  final Offset pan;
  final StrokePainter inner;
  final Size sheet;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);
    inner.paint(canvas, sheet);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheetPainter old) => true;
}

class _PadChip extends StatelessWidget {
  const _PadChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        color: Colors.black87,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the person pick a sticker to stick on the sheet.
Future<String?> pickDrawSticker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * 0.6,
          ),
          child: ListView(
            padding: const EdgeInsets.all(12),
            shrinkWrap: true,
            children: [
              for (final pack in stickerPacks) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 4),
                  child: Text(
                    pack.name.toUpperCase(),
                    style: AppTextStyles.eyebrow,
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in pack.stickers)
                      GestureDetector(
                        key: ValueKey('draw-sticker-${s.id}'),
                        onTap: () => Navigator.pop(sheet, s.id),
                        child: StickerView(stickerId: s.id, size: 66),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

const _smoothingKey = 'draw.smoothing';

/// The smoothing last chosen, on any drawing screen.
Future<DrawSmoothing> loadDrawSmoothing() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_smoothingKey);
    return DrawSmoothing.values.firstWhere(
      (s) => s.name == name,
      orElse: () => DrawSmoothing.light,
    );
  } catch (_) {
    return DrawSmoothing.light;
  }
}

void saveDrawSmoothing(DrawSmoothing smoothing) {
  unawaited(
    SharedPreferences.getInstance()
        .then((p) => p.setString(_smoothingKey, smoothing.name))
        .catchError((Object _) => false),
  );
}
