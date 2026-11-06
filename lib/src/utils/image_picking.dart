import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    show ImagePickerPlatform;
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Uses Android's Photo Picker for photos and videos. Without this the plugin
/// opens the general file browser, which reopens the last folder used by any
/// picker: choosing an audio file sent the next Gallery to the audio folder.
void usePhotoPicker([ImagePickerPlatform? platform]) {
  final picker = platform ?? ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
}

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

/// The system's file browser, for what isn't in the phone's media library
/// (Google Drive, say). Android may close the app while it is open, and unlike
/// the Photo Picker nothing brings the choice back.
Future<GalleryPick?> browseMediaFiles({
  bool photos = true,
  int maxSide = 1280,
  int quality = 75,
  VoidCallback? onPicked,
}) async {
  final result = await FilePicker.pickFiles(
    type: photos ? FileType.media : FileType.video,
    allowMultiple: photos,
    dialogTitle: 'Choose a file',
  );
  final chosen = result?.files.where((f) => f.path != null).toList();
  if (chosen == null || chosen.isEmpty) return null;
  onPicked?.call();
  final images = <Uint8List>[];
  final videos = <XFile>[];
  for (final f in chosen.take(4)) {
    if (isPickedVideo(f.name, null)) {
      videos.add(XFile(f.path!, name: f.name));
    } else {
      images.add(
        await shrinkImage(
          await XFile(f.path!).readAsBytes(),
          maxSide: maxSide,
          quality: quality,
        ),
      );
    }
  }
  return (photos: images, videos: videos);
}
