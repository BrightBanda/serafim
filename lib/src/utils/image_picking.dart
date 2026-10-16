import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Lets the user pick a photo (gallery, plus camera on phones) and returns it
/// already shrunk to JPEG, or null if they cancelled.
Future<Uint8List?> pickShrunkImage(
  BuildContext context, {
  int maxSide = 1280,
  int quality = 75,

  /// Called as soon as a photo has been chosen, before it is shrunk — the cue
  /// to show a spinner for the slow part.
  VoidCallback? onPicked,
}) async {
  var source = ImageSource.gallery;

  if (_hasCamera) {
    final chosen = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Choose from gallery', style: AppTextStyles.body),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Take a photo', style: AppTextStyles.body),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return null;
    source = chosen;
  }

  final file = await ImagePicker().pickImage(
    source: source,
    // Lets the platform shrink huge photos before they hit memory;
    // shrinkImage then guarantees the result on every platform.
    maxWidth: maxSide.toDouble(),
    maxHeight: maxSide.toDouble(),
    imageQuality: quality,
  );
  if (file == null) return null;
  onPicked?.call();

  return shrinkImage(
    await file.readAsBytes(),
    maxSide: maxSide,
    quality: quality,
  );
}
