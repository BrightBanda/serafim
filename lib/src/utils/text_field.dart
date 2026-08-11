import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Labeled input field: small mono-caps label above a flat-bordered
/// field, matching the web version's `.field` / `.field input`.
///
/// UI only — takes a [controller] and display options, no validation
/// or submit logic lives in this widget.
class SerafimTextField extends StatelessWidget {
  const SerafimTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.autocorrect = false,
    this.onChanged,
    this.errorText,
    this.helperText,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;

  /// Validation message from the view model. Also recolors the border.
  final String? errorText;

  /// Standing hint about what this field accepts, shown while there is no
  /// error. Unlike [hintText] it survives once the user starts typing, so the
  /// rule is visible before it gets broken rather than only after.
  final String? helperText;

  /// Set false while a submit is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.fieldLabel),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(
              color: errorText == null ? AppColors.lineSoft : AppColors.rust,
              width: 1.5,
            ),
            borderRadius: BorderRadius.zero,
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            autocorrect: autocorrect,
            onChanged: onChanged,
            enabled: enabled,
            style: AppTextStyles.fieldInput,
            cursorColor: AppColors.primary,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTextStyles.fieldInput.copyWith(
                color: AppColors.textDim,
              ),
              border: InputBorder.none,
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.zero,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 12,
              ),
              suffixIcon: suffix,
            ),
          ),
        ),
        // An error replaces the helper rather than stacking on top of it —
        // two lines of small print under one field is noise.
        if (errorText != null) ...[
          const SizedBox(height: 5),
          Text(
            errorText!,
            style: AppTextStyles.fieldLabel.copyWith(color: AppColors.rustPale),
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: 5),
          Text(helperText!, style: AppTextStyles.fieldLabel),
        ],
      ],
    );
  }
}
