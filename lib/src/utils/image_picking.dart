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

/// Lets the user choose up to four gallery photos at once. Camera capture
/// remains available on phones and returns a one-photo selection.
Future<List<Uint8List>?> pickShrunkImages(
  BuildContext context, {
  int maxSide = 1280,
  int quality = 75,
  VoidCallback? onPicked,
}) async {
  final picker = ImagePicker();
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
              title: Text('Choose photos', style: AppTextStyles.body),
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

  final files = source == ImageSource.camera
      ? [
          if (await picker.pickImage(
                source: source,
                maxWidth: maxSide.toDouble(),
                maxHeight: maxSide.toDouble(),
                imageQuality: quality,
              )
              case final file?)
            file,
        ]
      : await picker.pickMultiImage(
          limit: 4,
          maxWidth: maxSide.toDouble(),
          maxHeight: maxSide.toDouble(),
          imageQuality: quality,
        );
  if (files.isEmpty) return null;
  onPicked?.call();

  return Future.wait(
    files.map(
      (file) async => shrinkImage(
        await file.readAsBytes(),
        maxSide: maxSide,
        quality: quality,
      ),
    ),
  );
}

/// What came back from the gallery: photos already shrunk, videos untouched.
typedef GalleryPick = ({List<Uint8List> photos, List<XFile> videos});

/// Whether a picked file is a video, from its type or else its name.
bool isPickedVideo(String name, String? mimeType) {
  if (mimeType != null) return mimeType.startsWith('video/');
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return const {
    'mp4',
    'm4v',
    'mov',
    'webm',
    'mkv',
    '3gp',
    'avi',
  }.contains(name.substring(dot + 1).toLowerCase());
}

/// Lets the person choose from their gallery, photos and videos together (up
/// to four). With [photos] false (a chat that can't take pictures), one video.
/// Null if they backed out.
Future<GalleryPick?> pickFromGallery({
  bool photos = true,
  int maxSide = 1280,
  int quality = 75,
  VoidCallback? onPicked,
}) async {
  final picker = ImagePicker();
  if (!photos) {
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return null;
    return (photos: const <Uint8List>[], videos: [video]);
  }
  final files = await picker.pickMultipleMedia(
    limit: 4,
    maxWidth: maxSide.toDouble(),
    maxHeight: maxSide.toDouble(),
    imageQuality: quality,
  );
  if (files.isEmpty) return null;
  onPicked?.call();
  final videos = [
    for (final f in files)
      if (isPickedVideo(f.name, f.mimeType)) f,
  ];
  final shrunk = await Future.wait([
    for (final f in files)
      if (!isPickedVideo(f.name, f.mimeType))
        f.readAsBytes().then(
          (bytes) => shrinkImage(bytes, maxSide: maxSide, quality: quality),
        ),
  ]);
  return (photos: shrunk, videos: videos);
}

/// Takes a photo with the camera, shrunk. Null if they backed out.
Future<Uint8List?> takeShrunkPhoto({
  int maxSide = 1280,
  int quality = 75,
  VoidCallback? onPicked,
}) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.camera,
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
