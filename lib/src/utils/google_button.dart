import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_colors.dart';
import 'package:serafim/src/utils/app_text_styles.dart';
import 'package:serafim/src/utils/google_G_icon.dart';

/// "Continue with Google" button — same flat/hard-shadow language as
/// [SerafimButton], but a neutral fill so it reads as the secondary
/// action. UI only: takes an [onPressed] callback, no auth logic here.
class GoogleButton extends StatelessWidget {
  const GoogleButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Google',
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
          borderRadius: BorderRadius.zero,
          boxShadow: const [
            BoxShadow(
              color: AppColors.line,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GoogleGIcon(size: 16),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppTextStyles.buttonLabel.copyWith(color: AppColors.text),
            ),
          ],
        ),
      ),
    );
  }
}
