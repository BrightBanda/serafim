import 'package:flutter/material.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// A Circle as a card: its name, what it is about, how big it is, and
/// whether you can join it.
class CircleCard extends StatelessWidget {
  const CircleCard({
    super.key,
    required this.circle,
    this.onOpen,
    this.onJoin,
    this.trailing,
  });

  final CircleSummary circle;
  final VoidCallback? onOpen;

  /// The join button. Null when there is nothing to do — you are already in,
  /// or the Circle is invite-only, or you are banned.
  final VoidCallback? onJoin;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Icon(circle: circle),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        circle.name,
                        style: AppTextStyles.fieldInput.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '${circle.memberCount} '
                            '${circle.memberCount == 1 ? 'member' : 'members'}',
                            style: AppTextStyles.smallDim,
                          ),
                          if (circle.category != null) ...[
                            Text(' · ', style: AppTextStyles.smallDim),
                            Text(
                              circle.category!,
                              style: AppTextStyles.smallDim,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (circle.description != null &&
                circle.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                circle.description!,
                style: AppTextStyles.smallDim,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _VisibilityTag(visibility: circle.visibility),
                const Spacer(),
                if (onJoin != null)
                  GestureDetector(
                    onTap: onJoin,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        border: Border.all(color: AppColors.line, width: 1.5),
                      ),
                      child: Text(
                        circle.joinLabel,
                        style: AppTextStyles.buttonLabel.copyWith(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.circle});

  final CircleSummary circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        circle.name.isEmpty ? '?' : circle.name.characters.first.toUpperCase(),
        style: AppTextStyles.fieldInput.copyWith(
          color: AppColors.primaryPale,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VisibilityTag extends StatelessWidget {
  const _VisibilityTag({required this.visibility});

  final CircleVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (visibility) {
      CircleVisibility.public => (Icons.public, AppColors.textDim),
      CircleVisibility.private => (Icons.lock_outline, AppColors.tealPale),
      CircleVisibility.inviteOnly => (Icons.mail_outline, AppColors.rustPale),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          visibility.label,
          style: AppTextStyles.smallDim.copyWith(color: color),
        ),
      ],
    );
  }
}
