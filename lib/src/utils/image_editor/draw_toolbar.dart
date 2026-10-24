import 'package:flutter/material.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

/// The pen controls shared by the picture editor and the scribble pad: the
/// seven colours, the three sizes, undo and clear.
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
  });

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
            for (var i = 0; i < drawWidths.length; i++)
              GestureDetector(
                key: ValueKey('draw-size-$i'),
                onTap: () => onWidth(i),
                child: Container(
                  width: 40,
                  height: 36,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: i == width ? Colors.white : Colors.white24,
                      width: i == width ? 2 : 1,
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
            IconButton(
              key: const ValueKey('draw-undo'),
              tooltip: 'Undo',
              icon: const Icon(Icons.undo, color: Colors.white),
              onPressed: hasStrokes ? onUndo : null,
            ),
            IconButton(
              key: const ValueKey('draw-clear'),
              tooltip: 'Clear all',
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              onPressed: hasStrokes ? onClear : null,
            ),
          ],
        ),
        if (extra != null) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: extra!),
        ],
      ],
    );
  }
}
