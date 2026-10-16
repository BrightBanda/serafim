import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Circular avatar placeholder with a small edit badge, plus an
/// "Upload photo" text button underneath. UI only — [onEditTap] and
/// [onUploadTap] are plain callbacks, no image picking happens here.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    super.key,
    this.onEditTap,
    this.onUploadTap,
    this.size = 88,
    this.imageProvider,
    this.busy = false,
    this.busyLabel = 'Please wait…',
  });

  final VoidCallback? onEditTap;
  final VoidCallback? onUploadTap;
  final double size;

  /// Optional actual photo once one's been picked — left null shows the
  /// placeholder gradient circle. Passing the image in is still just UI;
  /// picking/cropping it is the caller's job.
  final ImageProvider? imageProvider;

  /// True while a photo is being prepared or uploaded: dims the avatar, shows
  /// a spinner and ignores taps so it can't be started twice.
  final bool busy;
  final String busyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.line,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                  image: imageProvider != null
                      ? DecorationImage(
                          image: imageProvider!,
                          fit: BoxFit.cover,
                        )
                      : null,
                  gradient: imageProvider == null
                      ? SweepGradient(
                          colors: [
                            AppColors.rust,
                            AppColors.paperAlt,
                            AppColors.teal,
                            AppColors.primaryDeep,
                            AppColors.primary,
                          ],
                        )
                      : null,
                ),
              ),
              if (busy)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: size * 0.32,
                        height: size * 0.32,
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: -2,
                right: -2,
                child: GestureDetector(
                  onTap: busy ? null : onEditTap,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      border: Border.all(color: AppColors.line, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: busy ? null : onUploadTap,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            busy ? busyLabel : 'Upload photo',
            style: AppTextStyles.linkText,
          ),
        ),
      ],
    );
  }
}
