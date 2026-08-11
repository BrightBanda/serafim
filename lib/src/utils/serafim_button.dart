import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Primary action button. Flat corners, gradient fill, a hard
/// (non-blurred) offset shadow instead of a soft Material elevation —
/// this is the "sticker" shadow used throughout the design.
///
/// UI only: takes an [onPressed] callback, doesn't call anything itself.
class SerafimButton extends StatelessWidget {
  const SerafimButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fullWidth = true,
    this.isPrimary = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDeep],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color.fromARGB(255, 16, 21, 33),
                    const Color.fromARGB(255, 16, 21, 35),
                  ],
                ),
          border: Border.all(color: AppColors.line, width: 2),
          borderRadius: BorderRadius.zero,
          boxShadow: const [
            BoxShadow(
              color: AppColors.line,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(label, style: AppTextStyles.buttonLabel),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
