import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Labeled input field: small mono-caps label above a flat-bordered
/// field, matching the web version's `.field` / `.field input`.
/// Optional [footer] renders below the field (e.g. a char counter).
///
/// UI only — takes a [controller] and display options, no validation
/// or submit logic lives in this widget.
class UiTextField extends StatelessWidget {
  const UiTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.autocorrect = false,
    this.footer,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final bool autocorrect;
  final Widget? footer;

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
            border: Border.all(color: AppColors.lineSoft, width: 1.5),
            borderRadius: BorderRadius.zero,
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            autocorrect: autocorrect,
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
        if (footer != null) ...[
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerRight, child: footer!),
        ],
      ],
    );
  }
}
