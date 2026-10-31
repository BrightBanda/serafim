import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

class AttachmentSaveException implements Exception {
  const AttachmentSaveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Saves a chat image or video from the app's private storage to somewhere
/// the user can reach it: the photo gallery on phones, the Downloads folder on
/// desktop. Audio files go wherever the person chooses ([saveAudio]).
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

  /// A chat video: to the gallery on phones, Downloads on desktop.
  Future<String> saveVideo(
    String sourcePath, {
    required String senderLabel,
    required DateTime sentAt,
  }) async {
    final source = File(sourcePath);
    if (kIsWeb || !await source.exists()) {
      throw const AttachmentSaveException(
        'The video is no longer on this device.',
      );
    }
    final fileName = _fileName(
      senderLabel,
      sentAt,
      extension: _ext(sourcePath),
    );
    if (Platform.isAndroid || Platform.isIOS) {
      return _saveToGallery(source, fileName, video: true);
    }
    return _saveToDownloads(source, fileName);
  }

  /// A chat audio file, under the name it was sent with: phones ask where
  /// to put it (there is no gallery for audio); desktop uses Downloads.
  /// Returns null if the person backed out.
  Future<String?> saveAudio(
    String sourcePath, {
    required String fileName,
  }) async {
    final source = File(sourcePath);
    if (kIsWeb || !await source.exists()) {
      throw const AttachmentSaveException(
        'The audio is no longer on this device.',
      );
    }
    final name = _safeName(fileName, fallbackExtension: _ext(sourcePath));
    if (Platform.isAndroid || Platform.isIOS) {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save audio',
        fileName: name,
        bytes: await source.readAsBytes(),
      );
      return saved == null ? null : 'Saved $name';
    }
    return _saveToDownloads(source, name);
  }

  Future<String> _saveToGallery(
    File source,
    String fileName, {
    bool video = false,
  }) async {
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
        if (video) {
          await Gal.putVideo(named.path, album: 'Serafim');
        } else {
          await Gal.putImage(named.path, album: 'Serafim');
        }
      } finally {
        if (await named.exists()) await named.delete();
      }
      return 'Saved to your gallery (Serafim album)';
    } on GalException catch (e) {
      throw AttachmentSaveException(switch (e.type) {
        GalExceptionType.accessDenied =>
          'Permission to save photos was denied.',
        GalExceptionType.notEnoughSpace => 'Not enough storage space.',
        _ => video ? 'Could not save the video.' : 'Could not save the image.',
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

  static String _ext(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? 'bin' : path.substring(dot + 1).toLowerCase();
  }

  /// [name] without path separators or control characters, keeping (or
  /// adding) an extension.
  static String _safeName(String name, {required String fallbackExtension}) {
    var safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]+'), '_').trim();
    if (safe.isEmpty || safe.startsWith('.')) safe = 'serafim_audio$safe';
    if (!safe.contains('.')) safe = '$safe.$fallbackExtension';
    return safe;
  }

  /// `serafim_<sender>_<yyyyMMdd_HHmmss>.<extension>`
  static String _fileName(
    String senderLabel,
    DateTime sentAt, {
    String extension = 'jpg',
  }) {
    final t = sentAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final who = senderLabel
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'serafim_${who.isEmpty ? 'chat' : who}_$stamp.$extension';
  }

  /// Exposed for tests.
  static String fileNameFor(String senderLabel, DateTime sentAt) =>
      _fileName(senderLabel, sentAt);
}
