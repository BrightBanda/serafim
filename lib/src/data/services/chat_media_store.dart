import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/utils/image_editor/scribble.dart';

/// On-device storage for chat image attachments. Images never go to cloud
/// storage; the Isar row keeps the path (`localMediaPath`) and the bytes live
/// here in the app's documents directory.
class ChatMediaStore {
  const ChatMediaStore();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/chat_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes [bytes] as `<messageId>.<ext>` and returns the absolute path.
  /// The extension follows the actual format (so a GIF stays a .gif and keeps
  /// animating when saved to the gallery); [extension] overrides it.
  Future<String> save(
    String messageId,
    Uint8List bytes, {
    String? extension,
  }) async {
    final dir = await _dir();
    final file = File(
      '${dir.path}/$messageId.${extension ?? imageExtension(bytes)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Moves a finished recording into chat storage as `<messageId>.m4a`.
  Future<String> adoptRecording(String messageId, String tempPath) async {
    final dir = await _dir();
    final target = '${dir.path}/$messageId.m4a';
    final source = File(tempPath);
    try {
      return (await source.rename(target)).path;
    } on FileSystemException {
      // Different filesystem: copy, then remove the original.
      final copy = await source.copy(target);
      await source.delete();
      return copy.path;
    }
  }
}

/// The file extension for image [bytes], from their signature.
String imageExtension(Uint8List bytes) {
  bool starts(List<int> sig, [int at = 0]) {
    if (bytes.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (starts(const [0x89, 0x50, 0x4E, 0x47])) {
    // A scribble is a PNG with a label inside; it is kept under its own name
    // so the chat can show it as a drawing.
    return hasScribbleMarker(bytes) ? 'scribble.png' : 'png';
  }
  if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
      starts(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'webp';
  }
  return 'jpg';
}
