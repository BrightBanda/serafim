import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Simple top bar: optional back button + "SERAFIM" wordmark, with an
/// optional trailing widget (e.g. a "STEP 2 OF 3" label).
/// UI only — [onBack] is a plain callback, navigation is the caller's job.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.onBack,
    this.title = 'SERAFIM',
    this.trailing,
    this.titleFontSize = 15,
    this.titleWidget,
  });

  final VoidCallback? onBack;
  final String title;
  final Widget? trailing;
  final int titleFontSize;

  /// Replaces the text [title] (e.g. avatar + username on the left).
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    // The Scaffold hands the app bar the status-bar height on top of 56px, and
    // the app draws edge-to-edge, so the bar keeps its content below the status
    // bar itself while its background extends underneath it.
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.paperRaised, AppColors.paperAlt],
        ),
        border: Border(bottom: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: preferredSize.height - 2, // the 2px bottom border
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
                        border: Border.all(
                          color: AppColors.lineSoft,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        size: 14,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                if (titleWidget != null)
                  Expanded(child: titleWidget!)
                else ...[
                  Text(title, style: AppTextStyles.logo),
                  const Spacer(),
                ],
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
