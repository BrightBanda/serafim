import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Whether [path] is a GIF (by name: chat media is stored under its real
/// extension).
bool isGifPath(String path) => path.toLowerCase().endsWith('.gif');

/// A GIF from a file that plays a few times and then stops, as WhatsApp's
/// do, with a small replay button.
///
/// An endlessly looping GIF keeps decoding frames and repainting for as long
/// as it is on screen — with several in a chat or the sticker panel that is
/// steady CPU, battery and memory for nothing. This decodes one frame at a
/// time, at the size it is shown ([cacheWidth]), keeps only the current
/// frame, and stops after [loops] plays. A file that isn't animated simply
/// shows its picture.
class LimitedGif extends StatefulWidget {
  const LimitedGif({
    super.key,
    required this.path,
    this.loops = 5,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.showReplay = true,
    this.errorBuilder,
  });

  final String path;
  final int loops;
  final BoxFit fit;

  /// Decode at this width (pixels), like [Image.cacheWidth].
  final int? cacheWidth;

  /// Offer a replay button once it has stopped. Off where a tap already
  /// means something else (e.g. sending it from the sticker panel).
  final bool showReplay;
  final WidgetBuilder? errorBuilder;

  @override
  State<LimitedGif> createState() => _LimitedGifState();
}

class _LimitedGifState extends State<LimitedGif> {
  ui.Codec? _codec;
  ui.Image? _frame;
  Timer? _timer;
  int _shown = 0;
  bool _stopped = false;
  bool _failed = false;

  /// Bumped on every reload, so a slow decode for an old file is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LimitedGif old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.cacheWidth != widget.cacheWidth) {
      _reset();
      _load();
    }
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  void _reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _codec?.dispose();
    _codec = null;
    _frame?.dispose();
    _frame = null;
    _shown = 0;
    _stopped = false;
    _failed = false;
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final bytes = await File(widget.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: widget.cacheWidth,
      );
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }
      _codec = codec;
      await _next(generation);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  Future<void> _next(int generation) async {
    final codec = _codec;
    if (codec == null) return;
    final ui.FrameInfo info;
    try {
      info = await codec.getNextFrame();
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
      return;
    }
    if (!mounted || generation != _generation) {
      info.image.dispose();
      return;
    }
    setState(() {
      _frame?.dispose();
      _frame = info.image;
    });
    _shown++;
    final frames = codec.frameCount;
    if (frames <= 1) return; // A still picture.
    if (_shown >= frames * widget.loops) {
      setState(() => _stopped = true);
      return;
    }
    // Browsers treat very short delays as 100 ms; so do we.
    final delay = info.duration < const Duration(milliseconds: 20)
        ? const Duration(milliseconds: 100)
        : info.duration;
    _timer = Timer(delay, () => _next(generation));
  }

  void _replay() {
    if (!_stopped) return;
    setState(() {
      _stopped = false;
      _shown = 0;
    });
    _next(_generation);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorBuilder?.call(context) ??
          const Icon(Icons.broken_image_outlined);
    }
    final frame = _frame;
    if (frame == null) return const SizedBox.shrink();
    final image = RawImage(image: frame, fit: widget.fit);
    if (!_stopped || !widget.showReplay) return image;
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.center,
      children: [
        image,
        Semantics(
          button: true,
          label: 'Play GIF again',
          child: GestureDetector(
            onTap: _replay,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0x80000000),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.replay, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}
