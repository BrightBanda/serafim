import 'package:flutter/material.dart';

/// What a chat's background is made of.
enum WallpaperKind { doodles, plain, color, gradient, image }

/// A chat background: the doodle pattern (default), the plain theme colour, a
/// preset colour or gradient, or a photo from the gallery stored on this
/// device. Stored as a short string (see [encode]).
class ChatWallpaper {
  const ChatWallpaper._(this.kind, [this.value, this.opacity = 1.0]);

  static const doodles = ChatWallpaper._(WallpaperKind.doodles);
  static const plain = ChatWallpaper._(WallpaperKind.plain);

  factory ChatWallpaper.color(String presetId, {double opacity = 1}) =>
      ChatWallpaper._(WallpaperKind.color, presetId, _clamp(opacity));
  factory ChatWallpaper.gradient(String presetId, {double opacity = 1}) =>
      ChatWallpaper._(WallpaperKind.gradient, presetId, _clamp(opacity));
  factory ChatWallpaper.image(String path, {double opacity = 1}) =>
      ChatWallpaper._(WallpaperKind.image, path, _clamp(opacity));

  /// The weakest a background may be shown: below this it would just look
  /// like the plain theme colour.
  static const minOpacity = 0.2;

  static double _clamp(double v) => v.clamp(minOpacity, 1.0).toDouble();

  final WallpaperKind kind;

  /// Preset id for colours and gradients, file path for images.
  final String? value;

  /// How strongly the background shows over the theme colour, 0.2 to 1.0.
  /// Doodles and plain ignore it. Kept apart from [value] so the image path
  /// stays a plain path (storage clean-up reads it).
  final double opacity;

  /// Whether the slider does anything for this background.
  bool get supportsOpacity =>
      kind != WallpaperKind.doodles && kind != WallpaperKind.plain;

  /// The same background shown at [value] strength.
  ChatWallpaper copyWithOpacity(double value) =>
      supportsOpacity ? ChatWallpaper._(kind, this.value, _clamp(value)) : this;

  /// Whether [other] is the same background, whatever its strength.
  bool sameBackground(ChatWallpaper other) =>
      other.kind == kind && other.value == value;

  /// `kind`, `kind:value` or `kind:value@opacity` (the suffix is left off at
  /// full strength, so older saved strings stay valid).
  String encode() {
    final base = value == null ? kind.name : '${kind.name}:$value';
    return opacity == 1.0 ? base : '$base@${opacity.toStringAsFixed(2)}';
  }

  /// Anything unreadable (an older or newer format) falls back to doodles.
  static ChatWallpaper decode(String? raw) {
    if (raw == null || raw.isEmpty) return doodles;
    // The strength is after the LAST '@', and only if it reads as a number.
    var opacity = 1.0;
    final at = raw.lastIndexOf('@');
    if (at > 0) {
      final parsed = double.tryParse(raw.substring(at + 1));
      if (parsed != null) {
        opacity = _clamp(parsed);
        raw = raw.substring(0, at);
      }
    }
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
            ? ChatWallpaper.color(value, opacity: opacity)
            : doodles;
      case WallpaperKind.gradient:
        return value != null && wallpaperGradients.containsKey(value)
            ? ChatWallpaper.gradient(value, opacity: opacity)
            : doodles;
      case WallpaperKind.image:
        return value != null && value.isNotEmpty
            ? ChatWallpaper.image(value, opacity: opacity)
            : doodles;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ChatWallpaper &&
      other.kind == kind &&
      other.value == value &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(kind, value, opacity);
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
