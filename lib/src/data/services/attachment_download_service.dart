import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

class AttachmentSaveException implements Exception {
  const AttachmentSaveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Saves a chat image from the app's private storage to somewhere the user
/// can reach it: the photo gallery on phones, the Downloads folder on desktop.
///
/// Chat images live only on-device (the server keeps them just until the
/// recipient has them), so "download" is an export of the local copy. Access
/// is already scoped to the conversation, since a device only ever holds
/// attachments it was sent or received.
class AttachmentDownloadService {
  const AttachmentDownloadService();

  /// Returns a short description of where the file went.
  Future<String> saveImage(
    String sourcePath, {
    required String senderLabel,
    required DateTime sentAt,
  }) async {
    final source = File(sourcePath);
    if (kIsWeb || !await source.exists()) {
      throw const AttachmentSaveException(
        'The image is no longer on this device.',
      );
    }

    final fileName = _fileName(senderLabel, sentAt);

    if (Platform.isAndroid || Platform.isIOS) {
      return _saveToGallery(source, fileName);
    }
    return _saveToDownloads(source, fileName);
  }

  Future<String> _saveToGallery(File source, String fileName) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          throw const AttachmentSaveException(
            'Permission to save photos was denied.',
          );
        }
      }
      // Gal names the saved file after the source, so give it the meaningful
      // name first. The gallery de-duplicates, so nothing is overwritten.
      final temp = await getTemporaryDirectory();
      final named = await source.copy('${temp.path}/$fileName');
      try {
        await Gal.putImage(named.path, album: 'Serafim');
      } finally {
        if (await named.exists()) await named.delete();
      }
      return 'Saved to your gallery (Serafim album)';
    } on GalException catch (e) {
      throw AttachmentSaveException(switch (e.type) {
        GalExceptionType.accessDenied =>
          'Permission to save photos was denied.',
        GalExceptionType.notEnoughSpace => 'Not enough storage space.',
        _ => 'Could not save the image.',
      });
    }
  }

  Future<String> _saveToDownloads(File source, String fileName) async {
    final dir = await getDownloadsDirectory();
    if (dir == null) {
      throw const AttachmentSaveException('No Downloads folder is available.');
    }
    final target = await _uniqueFile(dir, fileName);
    await source.copy(target.path);
    return 'Saved to ${target.path}';
  }

  /// `name.jpg`, or `name (1).jpg`, `name (2).jpg`… — never overwrites.
  Future<File> _uniqueFile(Directory dir, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot < 0 ? fileName : fileName.substring(0, dot);
    final ext = dot < 0 ? '' : fileName.substring(dot);
    var candidate = File('${dir.path}/$fileName');
    for (var i = 1; await candidate.exists(); i++) {
      candidate = File('${dir.path}/$stem ($i)$ext');
    }
    return candidate;
  }

  /// `serafim_<sender>_<yyyyMMdd_HHmmss>.jpg`
  static String _fileName(String senderLabel, DateTime sentAt) {
    final t = sentAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final who = senderLabel
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'serafim_${who.isEmpty ? 'chat' : who}_$stamp.jpg';
  }

  /// Exposed for tests.
  static String fileNameFor(String senderLabel, DateTime sentAt) =>
      _fileName(senderLabel, sentAt);
}
