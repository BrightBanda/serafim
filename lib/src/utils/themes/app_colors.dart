import 'package:flutter/material.dart';

/// One complete set of Serafim colors.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.ink,
    required this.paper,
    required this.paperAlt,
    required this.paperRaised,
    required this.line,
    required this.lineSoft,
    required this.primary,
    required this.primaryDeep,
    required this.primaryPale,
    required this.rust,
    required this.rustPale,
    required this.teal,
    required this.tealPale,
    required this.text,
    required this.textDim,
  });

  final Brightness brightness;

  // Backgrounds
  final Color ink;
  final Color paper;
  final Color paperAlt;
  final Color paperRaised;

  // Borders — navy ink, not flat black
  final Color line;
  final Color lineSoft;

  // Primary (blue)
  final Color primary;
  final Color primaryDeep;
  final Color primaryPale;

  // Secondary accents
  final Color rust;
  final Color rustPale;
  final Color teal;
  final Color tealPale;

  // Foreground
  final Color text;
  final Color textDim;

  /// The original dark theme — mirrors the web mockup's CSS custom properties.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    ink: Color(0xFF0C0D11),
    paper: Color(0xFF15161C),
    paperAlt: Color(0xFF1A1B22),
    paperRaised: Color(0xFF20222A),
    line: Color(0xFF1C2440),
    lineSoft: Color(0xFF33395C),
    primary: Color(0xFF5B7FD6),
    primaryDeep: Color(0xFF3D5AAD),
    primaryPale: Color(0xFFA9C0F0),
    rust: Color(0xFFB3562F),
    rustPale: Color(0xFFD98A63),
    teal: Color(0xFF3F7D78),
    tealPale: Color(0xFF7FB8B0),
    text: Color(0xFFD7D9E2),
    textDim: Color(0xFF8A8D9C),
  );

  /// Light counterpart: same navy ink borders and brand blue, on paper-white
  /// surfaces. The "pale" accents (used as text on dark) become deeper tones
  /// so they stay readable on light backgrounds.
  static const light = AppPalette(
    brightness: Brightness.light,
    ink: Color(0xFFFFFFFF),
    paper: Color(0xFFF1F2F7),
    paperAlt: Color(0xFFFFFFFF),
    paperRaised: Color(0xFFE6E9F3),
    line: Color(0xFF1C2440),
    lineSoft: Color(0xFFB9BFD6),
    primary: Color(0xFF4A6FC8),
    primaryDeep: Color(0xFF2F4A9A),
    primaryPale: Color(0xFF30479A),
    rust: Color(0xFFB3562F),
    rustPale: Color(0xFFA1431F),
    teal: Color(0xFF3F7D78),
    tealPale: Color(0xFF2B6762),
    text: Color(0xFF1B1E2B),
    textDim: Color(0xFF5B6075),
  );
}

/// Serafim color tokens.
///
/// These are getters over the *active* [AppPalette], not compile-time
/// constants, so the whole app can switch between light and dark at runtime.
/// Call [apply] to switch; the app then rebuilds itself (see `SerafimApp`).
class AppColors {
  AppColors._();

  static AppPalette _palette = AppPalette.dark;

  static AppPalette get palette => _palette;
  static Brightness get brightness => _palette.brightness;
  static bool get isLight => _palette.brightness == Brightness.light;

  static void apply(Brightness brightness) {
    _palette = brightness == Brightness.light
        ? AppPalette.light
        : AppPalette.dark;
  }

  // Backgrounds
  static Color get ink => _palette.ink;
  static Color get paper => _palette.paper;
  static Color get paperAlt => _palette.paperAlt;
  static Color get paperRaised => _palette.paperRaised;

  // Borders
  static Color get line => _palette.line;
  static Color get lineSoft => _palette.lineSoft;

  // Primary (blue)
  static Color get primary => _palette.primary;
  static Color get primaryDeep => _palette.primaryDeep;
  static Color get primaryPale => _palette.primaryPale;

  // Secondary accents
  static Color get rust => _palette.rust;
  static Color get rustPale => _palette.rustPale;
  static Color get teal => _palette.teal;
  static Color get tealPale => _palette.tealPale;

  // Foreground
  static Color get text => _palette.text;
  static Color get textDim => _palette.textDim;
}
