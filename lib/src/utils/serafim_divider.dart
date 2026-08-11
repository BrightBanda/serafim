import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_colors.dart';
import 'package:serafim/src/utils/app_text_styles.dart';

/// "or" divider used between the form and the Google button.
class SerafimDivider extends StatelessWidget {
  const SerafimDivider({super.key, this.label = 'or'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: AppColors.lineSoft, thickness: 1.5, height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label.toUpperCase(), style: AppTextStyles.fieldLabel),
        ),
        const Expanded(
          child: Divider(color: AppColors.lineSoft, thickness: 1.5, height: 1),
        ),
      ],
    );
  }
}
