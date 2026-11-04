import 'package:flutter/material.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

// The pickers a Circle's details are made with, on the create and edit
// screens alike.

/// One choice among a few (a category).
class CircleChoiceChip extends StatelessWidget {
  const CircleChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.paperRaised : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.lineSoft,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.fieldLabel.copyWith(
            color: selected ? AppColors.primaryPale : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}

/// Who can join, with a line about what it means.
class CircleVisibilityOption extends StatelessWidget {
  const CircleVisibilityOption({
    super.key,
    required this.visibility,
    required this.selected,
    required this.onTap,
  });

  final CircleVisibility visibility;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? AppColors.paperRaised : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.lineSoft,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              visibility.label.toUpperCase(),
              style: AppTextStyles.fieldLabel.copyWith(
                color: selected ? AppColors.primaryPale : AppColors.textDim,
              ),
            ),
            const SizedBox(height: 3),
            Text(visibility.blurb, style: AppTextStyles.smallDim),
          ],
        ),
      ),
    );
  }
}
