import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/announcement.dart';

/// Talks to the backend's `/official` routes: the official SERAFIM chat.
class OfficialService {
  const OfficialService(this._dio);

  final Dio _dio;

  Future<OfficialChatInfo> info() async {
    final data = await _call(() => _dio.get<dynamic>('/official'));
    if (data is! Map<String, dynamic>) {
      throw const ApiException('The server sent an unexpected response.');
    }
    return OfficialChatInfo.fromJson(data);
  }

  /// Newest first; [before] pages further back.
  Future<List<Announcement>> announcements({
    DateTime? before,
    int limit = 50,
  }) async {
    final data = await _call(
      () => _dio.get<dynamic>(
        '/official/announcements',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
      ),
    );
    if (data is! List) {
      throw const ApiException('The server sent an unexpected response.');
    }
    return [
      for (final json in data)
        Announcement.fromJson(json as Map<String, dynamic>),
    ];
  }

  /// Administrators only; the server answers 403 for anyone else.
  Future<Announcement> post(String content) async {
    final data = await _call(
      () => _dio.post<dynamic>(
        '/official/announcements',
        data: {'content': content},
      ),
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('The server sent an unexpected response.');
    }
    return Announcement.fromJson(data);
  }

  Future<void> delete(String id) async {
    await _call(() => _dio.delete<dynamic>('/official/announcements/$id'));
  }

  Future<Object?> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
