import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/doodle_kit.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// A sticker: the drawing on a white die-cut disc. With [animate] stickers
/// that have a [StickerMotion] move gently (unless the system asks for
/// reduced motion). Unknown ids show a small placeholder.
class StickerView extends StatefulWidget {
  const StickerView({
    super.key,
    required this.stickerId,
    this.size = 120,
    this.animate = false,
  });

  final String stickerId;
  final double size;
  final bool animate;

  @override
  State<StickerView> createState() => _StickerViewState();
}

class _StickerViewState extends State<StickerView>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  Sticker? get _sticker => stickerById(widget.stickerId);

  bool get _moves =>
      widget.animate &&
      (_sticker?.motion ?? StickerMotion.none) != StickerMotion.none;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StickerView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_moves && !reduce) {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sticker = _sticker;
    final size = widget.size;
    if (sticker == null) return _Unavailable(size: size);

    final art = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: StickerPainter(sticker),
      ),
    );
    final controller = _controller;
    return Semantics(
      image: true,
      label: '${sticker.name} sticker',
      child: SizedBox.square(
        dimension: size,
        child: controller == null
            ? art
            : AnimatedBuilder(
                animation: controller,
                child: art,
                builder: (_, child) =>
                    _move(sticker.motion, controller.value, size, child!),
              ),
      ),
    );
  }

  static Widget _move(StickerMotion m, double t, double size, Widget child) {
    final wave = math.sin(t * 2 * math.pi);
    switch (m) {
      case StickerMotion.bounce:
        return Transform.translate(
          offset: Offset(0, -size * 0.06 * wave.abs()),
          child: child,
        );
      case StickerMotion.wobble:
        return Transform.rotate(angle: 0.12 * wave, child: child);
      case StickerMotion.pulse:
        return Transform.scale(scale: 1 + 0.06 * wave, child: child);
      case StickerMotion.float:
        return Transform.translate(
          offset: Offset(size * 0.02 * wave, size * 0.04 * wave),
          child: child,
        );
      case StickerMotion.none:
        return child;
    }
  }
}

/// Paints a sticker scaled to fit, centred on its measured bounds.
class StickerPainter extends CustomPainter {
  StickerPainter(this.sticker);

  final Sticker sticker;
  static final _ink = DoodleInk.sticker();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = size.center(Offset.zero);

    // The die-cut backing: a white disc with a navy edge and a hard shadow.
    canvas.drawCircle(
      centre + Offset(r * 0.05, r * 0.05),
      r * 0.92,
      Paint()..color = const Color(0xFF1C2440),
    );
    canvas.drawCircle(centre, r * 0.92, Paint()..color = Colors.white);
    canvas.drawCircle(
      centre,
      r * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.04
        ..color = const Color(0xFF1C2440),
    );

    final b = sticker.bounds;
    final scale = (r * 0.74) / b.radius;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale);
    canvas.translate(-b.cx, -b.cy);
    sticker.draw(canvas, _ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(StickerPainter old) => old.sticker.id != sticker.id;
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.lineSoft, width: 1.5),
      ),
      child: Text(
        'STICKER\nUNAVAILABLE',
        textAlign: TextAlign.center,
        style: AppTextStyles.fieldLabel.copyWith(fontSize: 8),
      ),
    );
  }
}
