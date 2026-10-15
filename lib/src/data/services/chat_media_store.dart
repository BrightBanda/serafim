import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

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

  /// Writes [bytes] as `<messageId>.jpg` and returns the absolute path.
  Future<String> save(String messageId, Uint8List bytes) async {
    final dir = await _dir();
    final file = File('${dir.path}/$messageId.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
