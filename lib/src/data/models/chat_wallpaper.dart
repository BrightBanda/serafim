import 'package:flutter/material.dart';

/// What a chat's background is made of.
enum WallpaperKind { doodles, plain, color, gradient, image }

/// A chat background: the doodle pattern (default), the plain theme colour, a
/// preset colour or gradient, or a photo from the gallery stored on this
/// device. Stored as a short string (see [encode]).
class ChatWallpaper {
  const ChatWallpaper._(this.kind, [this.value]);

  static const doodles = ChatWallpaper._(WallpaperKind.doodles);
  static const plain = ChatWallpaper._(WallpaperKind.plain);

  factory ChatWallpaper.color(String presetId) =>
      ChatWallpaper._(WallpaperKind.color, presetId);
  factory ChatWallpaper.gradient(String presetId) =>
      ChatWallpaper._(WallpaperKind.gradient, presetId);
  factory ChatWallpaper.image(String path) =>
      ChatWallpaper._(WallpaperKind.image, path);

  final WallpaperKind kind;

  /// Preset id for colours and gradients, file path for images.
  final String? value;

  String encode() => value == null ? kind.name : '${kind.name}:$value';

  /// Anything unreadable (an older or newer format) falls back to doodles.
  static ChatWallpaper decode(String? raw) {
    if (raw == null || raw.isEmpty) return doodles;
    final i = raw.indexOf(':');
    final name = i < 0 ? raw : raw.substring(0, i);
    final value = i < 0 ? null : raw.substring(i + 1);
    final kind = WallpaperKind.values.where((k) => k.name == name).firstOrNull;
    switch (kind) {
      case WallpaperKind.doodles || null:
        return doodles;
      case WallpaperKind.plain:
        return plain;
      case WallpaperKind.color:
        return value != null && wallpaperColors.containsKey(value)
            ? ChatWallpaper.color(value)
            : doodles;
      case WallpaperKind.gradient:
        return value != null && wallpaperGradients.containsKey(value)
            ? ChatWallpaper.gradient(value)
            : doodles;
      case WallpaperKind.image:
        return value != null && value.isNotEmpty
            ? ChatWallpaper.image(value)
            : doodles;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ChatWallpaper && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Preset colours: muted enough that the opaque message bubbles always stand
/// out, in both light and dark mode.
const Map<String, Color> wallpaperColors = {
  'midnight': Color(0xFF111827),
  'plum': Color(0xFF2A1B3D),
  'forest': Color(0xFF15302A),
  'slate': Color(0xFF2B3442),
  'sand': Color(0xFFE9DFC9),
  'sky': Color(0xFFCFE3F5),
  'blush': Color(0xFFF3D9DE),
  'mint': Color(0xFFD5EDE3),
};

const Map<String, List<Color>> wallpaperGradients = {
  'aurora': [Color(0xFF1F2B5B), Color(0xFF3F7D78)],
  'dusk': [Color(0xFF4D44B6), Color(0xFFB3562F)],
  'ocean': [Color(0xFF0E3B5C), Color(0xFF5B7FD6)],
  'night': [Color(0xFF0C0D11), Color(0xFF33395C)],
  'peach': [Color(0xFFFFE1C6), Color(0xFFF7B7B0)],
  'lilac': [Color(0xFFE6E0FA), Color(0xFFBFD3F2)],
};
