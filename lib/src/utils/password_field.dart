import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/text_field.dart';

/// Password field with a Show/Hide text toggle, mirroring the web
/// version's `.pw-toggle`. The only state here is visibility — purely
/// presentational, no validation or auth logic.
class SerafimPasswordField extends StatefulWidget {
  const SerafimPasswordField({
    super.key,
    this.label = 'Password',
    this.controller,
    this.hintText,
    this.onChanged,
    this.errorText,
    this.helperText,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final String? helperText;
  final bool enabled;

  @override
  State<SerafimPasswordField> createState() => _SerafimPasswordFieldState();
}

class _SerafimPasswordFieldState extends State<SerafimPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return SerafimTextField(
      label: widget.label,
      controller: widget.controller,
      hintText: widget.hintText,
      obscureText: !_visible,
      onChanged: widget.onChanged,
      errorText: widget.errorText,
      helperText: widget.helperText,
      enabled: widget.enabled,
      suffix: TextButton(
        onPressed: widget.enabled
            ? () => setState(() => _visible = !_visible)
            : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          _visible ? 'HIDE' : 'SHOW',
          style: AppTextStyles.fieldLabel.copyWith(color: AppColors.textDim),
        ),
      ),
    );
  }
}
