import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serafim/src/data/models/chat_wallpaper.dart';
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

/// Draws a [ChatWallpaper]. Photos get a dimming (dark mode) or lightening
/// (light mode) layer on top, so the status line and any text drawn straight
/// on the background stay readable; bubbles are opaque either way.
class ChatWallpaperView extends StatelessWidget {
  const ChatWallpaperView({super.key, required this.wallpaper});

  final ChatWallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final layer = _layer();
    if (wallpaper.opacity >= 1.0) return layer;
    // Fainter: let the theme colour show through the background.
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: AppColors.paper),
        Opacity(opacity: wallpaper.opacity, child: layer),
      ],
    );
  }

  Widget _layer() {
    final value = wallpaper.value;
    switch (wallpaper.kind) {
      case WallpaperKind.doodles:
        return const ChatBackground();
      case WallpaperKind.plain:
        return ColoredBox(color: AppColors.paper);
      case WallpaperKind.color:
        return ColoredBox(color: wallpaperColors[value] ?? AppColors.paper);
      case WallpaperKind.gradient:
        final colors = wallpaperGradients[value];
        if (colors == null) return const ChatBackground();
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        );
      case WallpaperKind.image:
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(value!),
              fit: BoxFit.cover,
              // A missing file (cleared storage) falls back to the doodles.
              errorBuilder: (_, __, ___) => const ChatBackground(),
            ),
            ColoredBox(color: imageScrim),
          ],
        );
    }
  }

  /// The layer over photos that keeps things legible.
  static Color get imageScrim => AppColors.isLight
      ? Colors.white.withValues(alpha: 0.30)
      : Colors.black.withValues(alpha: 0.40);
}
