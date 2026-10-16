import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// What a person sees in place of a widget that crashed while drawing: a short
/// plain message instead of Flutter's grey box (or, in debug, a technical red
/// screen). Installed for release builds in `main()`.
class FriendlyErrorBox extends StatelessWidget {
  const FriendlyErrorBox({super.key});

  @override
  Widget build(BuildContext context) {
    // May render anywhere (even above a Theme or Directionality), so it brings
    // its own.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.paper,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sentiment_dissatisfied_outlined,
                  size: 30,
                  color: AppColors.textDim,
                ),
                const SizedBox(height: 10),
                Text(
                  "Something went wrong showing this part of the screen.\nGo back and try again.",
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
