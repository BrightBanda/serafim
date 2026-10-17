import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Marks the official SERAFIM account: a verified tick and an "OFFICIAL"
/// chip, so it can never be mistaken for a person who picked the name.
class OfficialBadge extends StatelessWidget {
  const OfficialBadge({super.key, this.compact = false});

  /// Tick only, for tight spaces.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tick = Icon(
      Icons.verified_rounded,
      size: 14,
      color: AppColors.primary,
    );
    if (compact) return tick;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tick,
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.primary,
            border: Border.all(color: AppColors.line, width: 1),
          ),
          child: Text(
            'OFFICIAL',
            style: AppTextStyles.fieldLabel.copyWith(
              fontSize: 7.5,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}
