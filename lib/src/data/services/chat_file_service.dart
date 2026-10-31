import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// The two kinds of file a chat can carry besides pictures and voice notes.
enum ChatFileKind { video, audio }

/// The largest video or audio file a chat accepts (the `chat-media` bucket
/// refuses anything bigger, and so does the server).
const maxChatFileBytes = 35 * 1024 * 1024;

/// Content types the server accepts, by file extension.
const _contentTypes = {
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'mkv': 'video/x-matroska',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'opus': 'audio/opus',
  'flac': 'audio/flac',
  'weba': 'audio/webm',
};

/// The content type to announce for a file of [kind] named [fileName], or
/// null when the server would not take it.
String? chatFileContentType(String fileName, ChatFileKind kind) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  final type = _contentTypes[fileName.substring(dot + 1).toLowerCase()];
  if (type == null || !type.startsWith('${kind.name}/')) return null;
  return type;
}

/// The extension to keep a downloaded file under, from its name.
String chatFileExtension(String? fileName, ChatFileKind kind) {
  final name = fileName ?? '';
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (_contentTypes.containsKey(ext)) return ext;
  return kind == ChatFileKind.video ? 'mp4' : 'm4a';
}

/// "4.2 MB", "820 KB".
String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb >= 10 ? mb.round() : mb.toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// A video or audio file the person picked to send.
class PickedChatFile {
  const PickedChatFile({
    required this.path,
    required this.name,
    required this.size,
    required this.kind,
    this.durationMs,
  });

  final String path;

  /// Its name on the device, shown to the people it is sent to.
  final String name;
  final int size;
  final ChatFileKind kind;
  final int? durationMs;
}

/// Today's upload allowance: voice notes, videos and audio files count;
/// forwards don't.
class ChatFileQuota {
  const ChatFileQuota({
    required this.used,
    required this.limit,
    required this.maxFile,
    required this.resetsAt,
  });

  factory ChatFileQuota.fromJson(Map<String, dynamic> json) => ChatFileQuota(
    used: (json['used'] as num).toInt(),
    limit: (json['limit'] as num).toInt(),
    maxFile: (json['max_file'] as num?)?.toInt() ?? maxChatFileBytes,
    resetsAt:
        DateTime.tryParse(json['resets_at'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
  );

  final int used;
  final int limit;
  final int maxFile;
  final DateTime resetsAt;

  int get remaining => used >= limit ? 0 : limit - used;
}

/// What the server knows about a video or audio file.
class ChatFileUpload {
  const ChatFileUpload({
    required this.id,
    required this.uploaded,
    this.uploadPath,
  });

  factory ChatFileUpload.fromJson(Map<String, dynamic> json) => ChatFileUpload(
    id: json['id'].toString(),
    uploaded: json['uploaded'] as bool? ?? true,
    uploadPath: json['upload_path'] as String?,
  );

  final String id;

  /// Whether the file is in storage and messages may refer to it.
  final bool uploaded;

  /// Where to upload it in the `chat-media` bucket, until [uploaded].
  final String? uploadPath;
}

/// Sends and fetches chat videos and audio files.
///
/// Sending is three steps, each safe to repeat after a dropped connection:
/// [announce] tells the server what is coming and gets a path in the
/// sender's own folder of the private `chat-media` bucket; [upload] sends the
/// file there directly (Supabase's resumable protocol, in 6 MB pieces, so a
/// video never passes through the API or sits in memory whole); and
/// [complete] has the server confirm it arrived. Downloads use a short-lived
/// signed link from [downloadUrl].
class ChatFileService {
  /// [_api] is the authenticated API client; [_storage] the authenticated
  /// Supabase Storage client.
  ChatFileService(
    this._api,
    this._storage, {
    Dio? downloader,
    this.chunkSize = 6 * 1024 * 1024,
  }) : _downloader = downloader ?? Dio();

  static const bucket = 'chat-media';

  final Dio _api;
  final Dio _storage;

  /// Plain client for signed links: they carry their own token, and the
  /// app's auth header must not go to them.
  final Dio _downloader;

  /// Supabase requires exactly 6 MB pieces (except the last).
  final int chunkSize;

  /// Resumable upload addresses by client id, so a retry in the same session
  /// continues where the last attempt stopped.
  final Map<String, String> _sessions = {};

  Future<ChatFileUpload> announce({
    required String clientId,
    required ChatFileKind kind,
    required String contentType,
    required int size,
    required String fileName,
    int durationMs = 0,
    Uint8List? thumbnail,
    String? recipientId,
    String? groupId,
  }) async {
    try {
      final response = await _api.post<dynamic>(
        '/media/files',
        data: {
          'client_id': clientId,
          'kind': kind.name,
          'content_type': contentType,
          'size': size,
          'file_name': fileName,
          'duration_ms': durationMs,
          if (thumbnail != null) 'thumbnail': base64Encode(thumbnail),
          if (recipientId != null) 'recipient_id': recipientId,
          if (groupId != null) 'group_id': groupId,
        },
      );
      return ChatFileUpload.fromJson(_map(response.data));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Uploads the file at [path] to [uploadPath]. Picks up an interrupted
  /// upload for the same [clientId] where it stopped.
  Future<void> upload({
    required String clientId,
    required String path,
    required String uploadPath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(path);
    final size = await file.length();
    try {
      var location = _sessions[clientId];
      int? offset;
      if (location != null) offset = await _offsetOf(location);
      if (location == null || offset == null) {
        location = await _create(uploadPath, contentType, size);
        if (location == null) {
          // Already there: an earlier attempt finished.
          onProgress?.call(1);
          return;
        }
        _sessions[clientId] = location;
        offset = 0;
      }

      final raf = await file.open();
      try {
        while (offset! < size) {
          await raf.setPosition(offset);
          final Uint8List chunk = await raf.read(chunkSize);
          final response = await _storage.patch<dynamic>(
            location,
            data: chunk,
            options: Options(
              headers: {
                'Tus-Resumable': '1.0.0',
                'Upload-Offset': '$offset',
                Headers.contentTypeHeader: 'application/offset+octet-stream',
                Headers.contentLengthHeader: chunk.length,
              },
              sendTimeout: const Duration(minutes: 2),
            ),
          );
          offset =
              int.tryParse(response.headers.value('upload-offset') ?? '') ??
              offset + chunk.length;
          onProgress?.call(offset / size);
        }
      } finally {
        await raf.close();
      }
      _sessions.remove(clientId);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Starts a resumable upload; returns its address, or null when the file
  /// is already in storage.
  Future<String?> _create(String path, String contentType, int size) async {
    String b64(String v) => base64Encode(utf8.encode(v));
    final response = await _storage.post<dynamic>(
      '/upload/resumable',
      options: Options(
        headers: {
          'Tus-Resumable': '1.0.0',
          'Upload-Length': '$size',
          'Upload-Metadata': [
            'bucketName ${b64(bucket)}',
            'objectName ${b64(path)}',
            'contentType ${b64(contentType)}',
            'cacheControl ${b64('3600')}',
          ].join(','),
        },
        validateStatus: (s) => s != null && (s < 300 || s == 409),
      ),
    );
    if (response.statusCode == 409) return null;
    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      throw const ApiException("Couldn't send that. Please try again.");
    }
    return location;
  }

  /// How much of an interrupted upload the server has, or null when it has
  /// forgotten it (then the upload starts again).
  Future<int?> _offsetOf(String location) async {
    try {
      final response = await _storage.head<dynamic>(
        location,
        options: Options(headers: {'Tus-Resumable': '1.0.0'}),
      );
      return int.tryParse(response.headers.value('upload-offset') ?? '');
    } on DioException {
      return null;
    }
  }

  Future<ChatFileUpload> complete(String mediaId) async {
    try {
      final response = await _api.post<dynamic>('/media/$mediaId/complete');
      return ChatFileUpload.fromJson(_map(response.data));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Copies media this person can read into another conversation (on the
  /// server: nothing is uploaded again). Works for voice notes too.
  Future<ChatFileUpload> forward(
    String mediaId, {
    required String clientId,
    String? recipientId,
    String? groupId,
  }) async {
    try {
      final response = await _api.post<dynamic>(
        '/media/$mediaId/forward',
        data: {
          'client_id': clientId,
          if (recipientId != null) 'recipient_id': recipientId,
          if (groupId != null) 'group_id': groupId,
        },
      );
      return ChatFileUpload.fromJson(_map(response.data));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ChatFileQuota> quota() async {
    try {
      final response = await _api.get<dynamic>('/media/usage');
      return ChatFileQuota.fromJson(_map(response.data));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<String> downloadUrl(String mediaId) async {
    try {
      final response = await _api.get<dynamic>('/media/$mediaId/url');
      final url = _map(response.data)['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const ApiException('Something went wrong. Please try again.');
      }
      return url;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Fetches [mediaId] into [savePath]. Nothing is left at [savePath]
  /// unless the whole file arrived.
  Future<void> download(
    String mediaId,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    final url = await downloadUrl(mediaId);
    final partial = '$savePath.part';
    try {
      await _downloader.download(
        url,
        partial,
        deleteOnError: true,
        options: Options(receiveTimeout: const Duration(minutes: 5)),
        onReceiveProgress: onProgress == null
            ? null
            : (received, total) {
                if (total > 0) onProgress(received / total);
              },
      );
      await File(partial).rename(savePath);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  static Map<String, dynamic> _map(Object? data) {
    if (data is Map<String, dynamic>) return data;
    throw const ApiException('Something went wrong. Please try again.');
  }
}
