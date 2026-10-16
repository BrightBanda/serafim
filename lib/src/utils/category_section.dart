import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// A labeled group of chips (Sports, Hobbies, Entertainment, etc) that opens
/// and closes. Purely presentational: whether it is [expanded] is owned by the
/// caller, who is told about taps through [onToggle].
///
/// A closed section still shows how many of its chips are selected
/// ([selectedCount]) so nothing is hidden from view.
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.expanded = true,
    this.onToggle,
    this.selectedCount = 0,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool expanded;
  final VoidCallback? onToggle;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: title,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                border: Border.all(
                  color: expanded ? AppColors.primary : AppColors.lineSoft,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: AppColors.tealPale),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: AppTextStyles.fieldLabel.copyWith(
                        color: AppColors.tealPale,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  if (selectedCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        border: Border.all(color: AppColors.line, width: 1),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: AppTextStyles.fieldLabel.copyWith(
                          color: Colors.white,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Wrap(spacing: 7, runSpacing: 7, children: children),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
