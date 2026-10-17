import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// What the server stored for an uploaded voice note.
class VoiceUpload {
  const VoiceUpload({
    required this.id,
    required this.durationMs,
    required this.waveform,
  });

  final String id;
  final int durationMs;
  final List<int> waveform;
}

/// Uploads and downloads voice notes (`/media`). Downloads are refused by the
/// server for anyone outside the conversation.
class MediaService {
  const MediaService(this._dio);

  final Dio _dio;

  /// Uploads a recording for a 1:1 chat ([recipientId]) or a group
  /// ([groupId]). [clientId] makes retries safe: the same id returns the first
  /// upload instead of storing a second copy.
  Future<VoiceUpload> uploadVoice({
    required Uint8List bytes,
    required String clientId,
    required int durationMs,
    required List<int> waveform,
    String? recipientId,
    String? groupId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/media/voice',
        data: Stream.fromIterable([bytes]),
        options: Options(
          contentType: 'audio/mp4',
          sendTimeout: const Duration(minutes: 2),
          headers: {
            Headers.contentLengthHeader: bytes.length,
            'x-client-id': clientId,
            'x-duration-ms': durationMs,
            'x-waveform': waveform.join(','),
            if (recipientId != null) 'x-recipient-id': recipientId,
            if (groupId != null) 'x-group-id': groupId,
          },
        ),
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total > 0) onProgress(sent / total);
              },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('The server sent an unexpected response.');
      }
      return VoiceUpload(
        id: data['id'].toString(),
        durationMs: data['duration_ms'] as int? ?? durationMs,
        waveform: [
          for (final v in (data['waveform'] as List? ?? const [])) v as int,
        ],
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Uint8List> download(String mediaId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/media/$mediaId',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
