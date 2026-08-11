import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Thin progress indicator used under the top bar during onboarding.
/// UI only — [progress] is just a 0.0–1.0 value the caller supplies.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(color: AppColors.paperAlt),
              Container(
                width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                color: AppColors.primary,
              ),
            ],
          );
        },
      ),
    );
  }
}
