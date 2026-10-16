import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Compact square button for card actions (Message, Add friend, Accept…).
/// [primary] fills it with the brand blue; otherwise it is an outlined
/// secondary action. A null [onPressed] renders it disabled.
class SmallActionButton extends StatelessWidget {
  const SmallActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final fg = primary ? Colors.white : AppColors.text;

    return Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: primary
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDeep],
                  )
                : null,
            color: primary ? null : AppColors.paper,
            border: Border.all(
              color: primary ? AppColors.line : AppColors.lineSoft,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: fg),
                )
              else if (icon != null)
                Icon(icon, size: 13, color: fg),
              if (busy || icon != null) const SizedBox(width: 5),
              Text(
                label,
                style: AppTextStyles.buttonLabel.copyWith(
                  fontSize: 10.5,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
