import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Text styles — same three-font system as the web mockup:
/// Bangers for display/headings, Inter for body/UI text,
/// JetBrains Mono for eyebrow labels and small caps.
///
/// Requires the `google_fonts` package in pubspec.yaml:
///   dependencies:
///     google_fonts: ^6.0.0
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get logo => GoogleFonts.bangers(
    color: AppColors.primaryPale,
    fontSize: 20,
    letterSpacing: 0.5,
  );

  static TextStyle get displayHeading => GoogleFonts.bangers(
    color: AppColors.text,
    fontSize: 26,
    letterSpacing: 0.5,
  );

  static TextStyle get eyebrow => GoogleFonts.jetBrainsMono(
    color: AppColors.primaryPale,
    fontSize: 10,
    letterSpacing: 1,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get body =>
      GoogleFonts.inter(color: AppColors.textDim, fontSize: 12, height: 1.5);

  static TextStyle get fieldLabel => GoogleFonts.jetBrainsMono(
    color: AppColors.textDim,
    fontSize: 9.5,
    letterSpacing: 0.5,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get fieldInput =>
      GoogleFonts.inter(color: AppColors.text, fontSize: 13);

  static TextStyle get buttonLabel => GoogleFonts.inter(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  static TextStyle get linkText => GoogleFonts.inter(
    color: AppColors.primaryPale,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static TextStyle get smallDim =>
      GoogleFonts.inter(color: AppColors.textDim, fontSize: 11);
}
