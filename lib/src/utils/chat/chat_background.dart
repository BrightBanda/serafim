import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/doodle_packing.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// The chat wallpaper: a packed scatter of goofy doodles — faces, food, objects
/// and small marks — drawn as faint marker line art.
///
/// Drawn in code from the active palette, so it is crisp at any size and
/// follows light/dark automatically. It is deliberately quiet: message bubbles
/// are opaque and always win. The doodle layout is precomputed (see
/// `doodle_packing.dart`), so showing it costs nothing at runtime.
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // Static art: cache it as one layer so scrolling messages never repaint it.
    return RepaintBoundary(
      child: CustomPaint(
        painter: ChatDoodlePainter(AppColors.palette),
        size: Size.infinite,
      ),
    );
  }
}
