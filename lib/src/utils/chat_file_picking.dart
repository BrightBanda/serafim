import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';

/// Why a picked file can't be sent; [message] is for the person.
class ChatFilePickException implements Exception {
  const ChatFilePickException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lets the person choose a video or audio file to send. Nothing is read
/// into memory: only its path, name and size. Returns null if they backed
/// out; throws [ChatFilePickException] when the file can't be sent (too big,
/// or a type the server won't take), so nothing is copied for nothing.
Future<PickedChatFile?> pickChatFile(ChatFileKind kind) async {
  final result = await FilePicker.pickFiles(
    type: kind == ChatFileKind.video ? FileType.video : FileType.audio,
    dialogTitle: kind == ChatFileKind.video ? 'Choose a video' : 'Choose audio',
  );
  final picked = result?.files.singleOrNull;
  final path = picked?.path;
  if (picked == null || path == null) return null;

  final size = picked.size > 0 ? picked.size : await File(path).length();
  final name = picked.name.isNotEmpty ? picked.name : path.split('/').last;
  return checkChatFile(
    PickedChatFile(path: path, name: name, size: size, kind: kind),
  );
}

/// [file] if it can be sent; otherwise throws [ChatFilePickException].
PickedChatFile checkChatFile(PickedChatFile file) {
  final what = file.kind == ChatFileKind.video ? 'video' : 'audio file';
  if (file.size > maxChatFileBytes) {
    throw ChatFilePickException(
      'That $what is ${formatFileSize(file.size)}. '
      'You can send up to ${formatFileSize(maxChatFileBytes)}.',
    );
  }
  if (file.size == 0) {
    throw ChatFilePickException('That $what is empty.');
  }
  if (chatFileContentType(file.name, file.kind) == null &&
      chatFileContentType(file.path, file.kind) == null) {
    throw ChatFilePickException(
      file.kind == ChatFileKind.video
          ? "That video format can't be sent. Try MP4, MOV or WebM."
          : "That audio format can't be sent. Try MP3, M4A, WAV, OGG or FLAC.",
    );
  }
  return file;
}
