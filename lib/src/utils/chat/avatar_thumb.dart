import 'package:flutter/material.dart';
import 'package:serafim/src/utils/halo_style.dart';
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
    this.halo = false,
  });

  final double size;
  final bool isGroup;
  final ImageProvider? imageProvider;

  /// Their halo is lit: a gold glow around the photo ("free to chat").
  final bool halo;

  @override
  Widget build(BuildContext context) {
    final photo = _photo(halo ? size - 7 : size);
    if (!halo) return photo;
    return Semantics(
      label: 'Halo on: free to chat',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: haloColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: haloColor.withValues(alpha: 0.55),
              blurRadius: 9,
              spreadRadius: 1,
            ),
          ],
        ),
        child: photo,
      ),
    );
  }

  Widget _photo(double size) {
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
                    ? [AppColors.teal, AppColors.paper, AppColors.primaryDeep]
                    : [AppColors.rust, AppColors.paper, AppColors.primary],
              )
            : null,
      ),
    );
  }
}
