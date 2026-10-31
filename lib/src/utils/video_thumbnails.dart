import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';

/// The server keeps video previews up to 48 KB.
const maxVideoThumbnailBytes = 48 * 1024;

/// Makes a small JPEG preview of the video at [path]: about 320 px wide, a
/// few tens of KB, so it can travel with the message.
///
/// Returns null where previews can't be made (desktop: the plugin covers
/// Android and iOS only) or when the video can't be read; the bubble then
/// shows a plain placeholder.
Future<Uint8List?> makeVideoThumbnail(String path) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
  try {
    for (final (width, quality) in const [(320, 60), (240, 40)]) {
      final bytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: width,
        quality: quality,
      );
      if (bytes.isNotEmpty && bytes.length <= maxVideoThumbnailBytes) {
        return bytes;
      }
    }
  } catch (_) {
    // A preview is a nicety: never let it stop a video being sent.
  }
  return null;
}
