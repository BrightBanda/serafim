import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// Small circular avatar placeholder. [isGroup] swaps the gradient so
/// group chats/communities read visually distinct from people, same
/// as the web mockup's `.thumb-sm.person` / `.thumb-sm.group`.
///
/// UI only — pass [imageProvider] once a real photo exists; leaving it
/// null shows the placeholder gradient.
class AvatarThumb extends StatelessWidget {
  const AvatarThumb({
    super.key,
    this.size = 38,
    this.isGroup = false,
    this.imageProvider,
  });

  final double size;
  final bool isGroup;
  final ImageProvider? imageProvider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.line, width: 1.5),
        image: imageProvider != null
            ? DecorationImage(image: imageProvider!, fit: BoxFit.cover)
            : null,
        gradient: imageProvider == null
            ? SweepGradient(
                colors: isGroup
                    ? const [
                        AppColors.teal,
                        AppColors.paper,
                        AppColors.primaryDeep,
                      ]
                    : const [
                        AppColors.rust,
                        AppColors.paper,
                        AppColors.primary,
                      ],
              )
            : null,
      ),
    );
  }
}
