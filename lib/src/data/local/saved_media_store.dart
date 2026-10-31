import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Files saved to sticker collections (GIFs, videos, audio), one folder per
/// account under the app's documents directory.
///
/// A file is named after its contents (`<sha1>.<ext>`), so saving the same
/// GIF into three collections stores it once, and "is it already saved?"
/// is a name comparison. Collections keep only that name; nothing large
/// ever goes into shared preferences.
class SavedMediaStore {
  SavedMediaStore({Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _baseDir;

  Future<Directory> dirFor(String account) async {
    final base = await _baseDir();
    final dir = Directory('${base.path}/saved_media/$account');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The name [sourcePath] would be saved under. Reads the file through
  /// once (streaming: videos can be large) without copying it.
  Future<String> nameFor(String sourcePath) async {
    final digest = await sha1.bind(File(sourcePath).openRead()).first;
    return '$digest.${_extension(sourcePath)}';
  }

  /// Copies [sourcePath] in as [name] (from [nameFor]) unless it is there.
  Future<void> adopt(String account, String sourcePath, String name) async {
    final target = File('${(await dirFor(account)).path}/$name');
    if (await target.exists()) return;
    // Copy to a temporary name first, so a half-written file is never
    // mistaken for a saved one.
    final partial = await File(sourcePath).copy('${target.path}.part');
    await partial.rename(target.path);
  }

  /// Saves [bytes] (an older collection's inline GIF); returns its name.
  Future<String> adoptBytes(
    String account,
    Uint8List bytes, {
    required String extension,
  }) async {
    final name = '${sha1.convert(bytes)}.$extension';
    final target = File('${(await dirFor(account)).path}/$name');
    if (!await target.exists()) await target.writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<String> pathOf(String account, String name) async =>
      '${(await dirFor(account)).path}/$name';

  Future<void> delete(String account, String name) async {
    try {
      final file = File(await pathOf(account, name));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _extension(String path) {
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    if (dot <= slash + 1) return 'bin';
    final ext = path.substring(dot + 1).toLowerCase();
    // `x.scribble.png` and the like keep only the last part.
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'bin';
  }
}
