import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_colors.dart';
import 'package:serafim/src/utils/app_text_styles.dart';

/// Simple top bar: optional back button + "SERAFIM" wordmark.
/// UI only — [onBack] is a plain callback, navigation is the caller's job.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key, this.onBack, this.title = 'SERAFIM'});

  final VoidCallback? onBack;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.paperRaised, AppColors.paperAlt],
        ),
        border: Border(bottom: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(color: AppColors.lineSoft, width: 1.5),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 14,
                  color: AppColors.text,
                ),
              ),
            ),
          Text(title, style: AppTextStyles.logo),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
