import 'package:flutter/material.dart';

/// Serafim color tokens — mirrors the CSS custom properties used in the
/// web mockup 1:1 so the two stay in sync if the palette changes.
class AppColors {
  AppColors._();

  // Backgrounds
  static const ink = Color(0xFF0C0D11);
  static const paper = Color(0xFF15161C);
  static const paperAlt = Color(0xFF1A1B22);
  static const paperRaised = Color(0xFF20222A);

  // Borders — navy ink, not flat black
  static const line = Color(0xFF1C2440);
  static const lineSoft = Color(0xFF33395C);

  // Primary (blue)
  static const primary = Color(0xFF5B7FD6);
  static const primaryDeep = Color(0xFF3D5AAD);
  static const primaryPale = Color(0xFFA9C0F0);

  // Secondary accents
  static const rust = Color(0xFFB3562F);
  static const rustPale = Color(0xFFD98A63);
  static const teal = Color(0xFF3F7D78);
  static const tealPale = Color(0xFF7FB8B0);

  // Foreground
  static const text = Color(0xFFD7D9E2);
  static const textDim = Color(0xFF8A8D9C);
}
