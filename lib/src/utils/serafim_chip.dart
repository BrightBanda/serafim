import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A single toggleable interest chip. Purely presentational — [selected]
/// and [onTap] are supplied by the parent, which owns the actual
/// selection state.
class SerafimChip extends StatelessWidget {
  const SerafimChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.paperAlt,
          border: Border.all(
            color: selected ? AppColors.line : AppColors.lineSoft,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: selected ? Colors.white : AppColors.textDim,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }
}
