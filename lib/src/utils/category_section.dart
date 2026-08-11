import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A labeled group of chips (Sports, Hobbies, Entertainment, etc).
/// Purely layout — [children] are whatever chip widgets the caller builds.
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: AppColors.tealPale),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: AppTextStyles.fieldLabel.copyWith(
                color: AppColors.tealPale,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: children),
      ],
    );
  }
}
