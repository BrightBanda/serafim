import 'package:flutter/material.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

/// The pen controls shared by the picture editor and the scribble pad: the
/// seven colours, the three pen sizes (or, while erasing, the three eraser
/// sizes), undo and clear.
///
/// It owns no state; the screen keeps the chosen colour and size and the
/// strokes, so this stays a plain view.
class DrawToolbar extends StatelessWidget {
  const DrawToolbar({
    super.key,
    required this.color,
    required this.width,
    required this.onColor,
    required this.onWidth,
    required this.hasStrokes,
    required this.onUndo,
    required this.onClear,
    this.extra,
    this.erasing = false,
    this.onEraser,
    this.eraserWidth = defaultEraserIndex,
    this.onEraserWidth,
    this.canRedo = false,
    this.onRedo,
    this.brush = Brush.pen,
    this.onBrush,
    this.smoothing = DrawSmoothing.off,
    this.onSmoothing,
    this.onSticker,
  });

  /// Brings back what Undo took. Only shown when [onRedo] is given.
  final bool canRedo;
  final VoidCallback? onRedo;

  /// The brush in use. The brushes are only shown when [onBrush] is given.
  final Brush brush;
  final ValueChanged<Brush>? onBrush;

  /// How much lines are steadied. Only shown when [onSmoothing] is given.
  final DrawSmoothing smoothing;
  final ValueChanged<DrawSmoothing>? onSmoothing;

  /// Opens the stickers. Only shown when given.
  final VoidCallback? onSticker;

  static const _brushIcons = {
    Brush.pen: Icons.edit,
    Brush.marker: Icons.brush,
    Brush.highlighter: Icons.border_color,
    Brush.ink: Icons.gesture,
  };

  /// Index into [drawColors] / [drawWidths].
  final int color;
  final int width;
  final ValueChanged<int> onColor;
  final ValueChanged<int> onWidth;

  /// Undo and Clear are off while there is nothing drawn.
  final bool hasStrokes;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  /// The eraser is in use (and no colour is selected). Only shown when
  /// [onEraser] is given.
  final bool erasing;

  /// Switches the eraser on or off.
  final VoidCallback? onEraser;

  /// Index into [eraserWidths]: the chosen eraser size, kept apart from the
  /// pen's so switching back to the pen keeps its size.
  final int eraserWidth;
  final ValueChanged<int>? onEraserWidth;

  /// Something more, on a row of its own below (e.g. a paper picker).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < drawColors.length; i++)
              GestureDetector(
                key: ValueKey('draw-color-$i'),
                onTap: () => onColor(i),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: drawColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: i == color && !erasing
                          ? Colors.white
                          : Colors.white24,
                      width: i == color && !erasing ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (erasing && onEraserWidth != null)
              // Eraser sizes: hollow circles, so they read as "rub out".
              for (var i = 0; i < eraserWidths.length; i++)
                _SizeButton(
                  key: ValueKey('draw-eraser-size-$i'),
                  selected: i == eraserWidth,
                  onTap: () => onEraserWidth!(i),
                  child: Container(
                    width: 10 + i * 8.0,
                    height: 10 + i * 8.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                )
            else
              for (var i = 0; i < drawWidths.length; i++)
                _SizeButton(
                  key: ValueKey('draw-size-$i'),
                  selected: i == width,
                  onTap: () => onWidth(i),
                  child: Container(
                    width: 8 + i * 6.0,
                    height: 8 + i * 6.0,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            if (onEraser != null)
              GestureDetector(
                key: const ValueKey('draw-eraser'),
                onTap: onEraser,
                child: Tooltip(
                  message: 'Eraser',
                  child: Container(
                    width: 40,
                    height: 36,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: erasing ? Colors.white24 : null,
                      border: Border.all(
                        color: erasing ? Colors.white : Colors.white24,
                        width: erasing ? 2 : 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            _action(
              const ValueKey('draw-undo'),
              'Undo',
              Icons.undo,
              hasStrokes ? onUndo : null,
            ),
            if (onRedo != null)
              _action(
                const ValueKey('draw-redo'),
                'Redo',
                Icons.redo,
                canRedo ? onRedo : null,
              ),
            _action(
              const ValueKey('draw-clear'),
              'Clear all',
              Icons.delete_sweep,
              hasStrokes ? onClear : null,
            ),
          ],
        ),
        if (onBrush != null || onSmoothing != null || onSticker != null) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (onBrush case final choose?)
                  for (final b in Brush.values)
                    Tooltip(
                      message: _brushName(b),
                      child: _SizeButton(
                        key: ValueKey('draw-brush-${b.name}'),
                        selected: b == brush && !erasing,
                        onTap: () => choose(b),
                        child: Icon(
                          _brushIcons[b],
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                if (onSticker case final open?)
                  Tooltip(
                    message: 'Stickers',
                    child: _SizeButton(
                      key: const ValueKey('draw-stickers'),
                      selected: false,
                      onTap: open,
                      child: const Icon(
                        Icons.emoji_emotions_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (onSmoothing case final choose?)
                  Tooltip(
                    message: 'Steadies your lines as you draw',
                    child: GestureDetector(
                      key: const ValueKey('draw-smoothing'),
                      onTap: () => choose(smoothing.next),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: smoothing == DrawSmoothing.off
                                ? Colors.white24
                                : Colors.white,
                            width: smoothing == DrawSmoothing.off ? 1 : 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.auto_fix_high,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Smooth\n${smoothing.label}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (extra != null) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: extra!),
        ],
      ],
    );
  }
}

String _brushName(Brush b) => switch (b) {
  Brush.pen => 'Pen',
  Brush.marker => 'Marker',
  Brush.highlighter => 'Highlighter',
  Brush.ink => 'Brush pen',
};

/// Undo, redo, clear: compact, so all three fit beside the sizes on a narrow
/// phone.
Widget _action(Key key, String tooltip, IconData icon, VoidCallback? onTap) =>
    IconButton(
      key: key,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 36),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, color: onTap == null ? Colors.white38 : Colors.white),
      onPressed: onTap,
    );

/// One size choice: a box with a preview of the line inside.
class _SizeButton extends StatelessWidget {
  const _SizeButton({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 36,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
