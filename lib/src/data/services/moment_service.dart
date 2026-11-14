import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/moment.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';

/// Talks to the backend's `/moments` routes. Who may see what, how long it
/// lasts and every limit are the server's; the app only shows the result.
class MomentService {
  const MomentService(this._dio);

  final Dio _dio;

  /// Posts a photo. [photo] and [thumbnail] are JPEGs, already shrunk.
  Future<Moment> postPhoto({
    required Uint8List photo,
    required Uint8List thumbnail,
    required MomentAudience audience,
    List<String> excludeIds = const [],
    String? caption,
    bool allowSave = true,
  }) => _post({
    'kind': 'photo',
    'photo': base64Encode(photo),
    'thumbnail': base64Encode(thumbnail),
    ..._shared(audience, excludeIds, caption, allowSave),
  });

  /// Step 1 of a video: where to upload it. Then upload, `complete` (the same
  /// call as for a chat video) and [postVideo].
  Future<ChatFileUpload> startVideo({
    required String clientId,
    required String contentType,
    required int size,
    required int durationMs,
    required Uint8List thumbnail,
  }) async => ChatFileUpload.fromJson(
    await _map(
      () => _dio.post<dynamic>(
        '/moments/video',
        data: {
          'client_id': clientId,
          'content_type': contentType,
          'size': size,
          'duration_ms': durationMs,
          'thumbnail': base64Encode(thumbnail),
        },
      ),
    ),
  );

  Future<Moment> postVideo({
    required String mediaId,
    required Uint8List thumbnail,
    required MomentAudience audience,
    List<String> excludeIds = const [],
    String? caption,
    bool allowSave = true,
  }) => _post({
    'kind': 'video',
    'media_id': mediaId,
    'thumbnail': base64Encode(thumbnail),
    ..._shared(audience, excludeIds, caption, allowSave),
  });

  Map<String, dynamic> _shared(
    MomentAudience audience,
    List<String> excludeIds,
    String? caption,
    bool allowSave,
  ) => {
    'visibility': audience.wire,
    'allow_save': allowSave,
    if (audience == MomentAudience.except) 'exclude_ids': excludeIds,
    if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
  };

  Future<Moment> _post(Map<String, dynamic> body) async => Moment.fromJson(
    await _map(() => _dio.post<dynamic>('/moments', data: body)),
  );

  /// Your own moments that are still showing.
  Future<List<Moment>> mine() => _moments('/moments/mine');

  /// [userId]'s moments you may see, oldest first.
  Future<List<Moment>> of(String userId) => _moments('/moments/users/$userId');

  Future<List<Moment>> _moments(String path) async {
    final data = await _call(() => _dio.get<dynamic>(path));
    if (data is! List) throw _unexpected;
    return data.map((m) => Moment.fromJson(m as Map<String, dynamic>)).toList();
  }

  /// Which of [userIds] have a moment you may see (at most 100 at a time).
  Future<List<MomentRing>> rings(Iterable<String> userIds) async {
    final ids = userIds.take(100).join(',');
    if (ids.isEmpty) return const [];
    return _rings('/moments/rings', {'user_ids': ids});
  }

  /// Friends with a moment showing, unseen first.
  Future<List<MomentRing>> feed() => _rings('/moments/feed');

  Future<List<MomentRing>> _rings(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final data = await _call(
      () => _dio.get<dynamic>(path, queryParameters: query),
    );
    if (data is! List) throw _unexpected;
    return data
        .map((r) => MomentRing.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// The picture of a photo moment (a JPEG).
  Future<Uint8List> photo(String id) async {
    try {
      final response = await _dio.get<List<int>>(
        '/moments/$id/photo',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// A short-lived link to play a video moment.
  Future<String> videoUrl(String id) async {
    final data = await _map(() => _dio.get<dynamic>('/moments/$id/video-url'));
    return data['url'] as String;
  }

  /// Records a look. With [private] (read receipts off) it counts for your own
  /// ring, but the owner isn't shown that you looked.
  Future<void> markSeen(String id, {bool private = false}) => _call(
    () => _dio.post<dynamic>(
      '/moments/$id/view',
      data: private ? {'private': true} : null,
    ),
  );

  Future<Moment> spark(String id) async => Moment.fromJson(
    await _map(() => _dio.post<dynamic>('/moments/$id/spark')),
  );

  Future<Moment> unspark(String id) async => Moment.fromJson(
    await _map(() => _dio.delete<dynamic>('/moments/$id/spark')),
  );

  /// Who looked at one of your moments, newest first.
  Future<MomentViewers> viewers(String id) async => MomentViewers.fromJson(
    await _map(() => _dio.get<dynamic>('/moments/$id/viewers')),
  );

  Future<void> delete(String id) =>
      _call(() => _dio.delete<dynamic>('/moments/$id'));

  static const _unexpected = ApiException(
    'Something went wrong. Please try again.',
  );

  Future<Map<String, dynamic>> _map(
    Future<Response<dynamic>> Function() request,
  ) async {
    final data = await _call(request);
    if (data is! Map<String, dynamic>) throw _unexpected;
    return data;
  }

  Future<Object?> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
