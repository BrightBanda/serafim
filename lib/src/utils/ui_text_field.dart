import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Labeled input field: small mono-caps label above a flat-bordered
/// field, matching the web version's `.field` / `.field input`.
/// Optional [footer] renders below the field. With [maxLength] and no footer,
/// a live "used / max" counter is shown there instead, and typing past the
/// limit is blocked.
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
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final bool autocorrect;
  final Widget? footer;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

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
            maxLength: maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            maxLines: maxLines,
            minLines: minLines,
            textCapitalization: textCapitalization,
            onChanged: onChanged,
            style: AppTextStyles.fieldInput,
            cursorColor: AppColors.primary,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTextStyles.fieldInput.copyWith(
                color: AppColors.textDim,
              ),
              border: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.zero,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 12,
              ),
              suffixIcon: suffix,
              // The counter is drawn below the box instead (see [footer]).
              counterText: '',
            ),
          ),
        ),
        if (footer != null || (maxLength != null && controller != null)) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: footer ?? _Counter(controller: controller!, max: maxLength!),
          ),
        ],
      ],
    );
  }
}

/// "used / max", turning to the warning colour at the limit.
class _Counter extends StatelessWidget {
  const _Counter({required this.controller, required this.max});

  final TextEditingController controller;
  final int max;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, __) {
        final used = value.text.characters.length;
        return Text(
          '$used / $max',
          style: AppTextStyles.fieldLabel.copyWith(
            fontSize: 8.5,
            color: used >= max ? AppColors.rustPale : AppColors.textDim,
          ),
        );
      },
    );
  }
}
