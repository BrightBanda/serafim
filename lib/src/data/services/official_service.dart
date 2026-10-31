import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_update.dart';

/// Talks to the backend's `/official` routes: the official SERAFIM chat.
class OfficialService {
  const OfficialService(this._dio);

  final Dio _dio;

  Future<OfficialChatInfo> info() async {
    final data = await _call(() => _dio.get<dynamic>('/official'));
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
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
      throw const ApiException('Something went wrong. Please try again.');
    }
    return [
      for (final json in data)
        Announcement.fromJson(json as Map<String, dynamic>),
    ];
  }

  /// Administrators only; the server answers 403 for anyone else. With
  /// [update] it announces an Android release (the text may then be empty).
  Future<Announcement> post(String content, {AppUpdate? update}) async {
    final data = await _call(
      () => _dio.post<dynamic>(
        '/official/announcements',
        data: {
          'content': content,
          if (update != null)
            'update': {
              'version_name': update.versionName,
              'version_code': update.versionCode,
              'changelog': update.changelog,
              'apk_url': update.apkUrl,
              'sha256': update.sha256,
              'size_bytes': update.sizeBytes,
              'mandatory': update.mandatory,
              'variants': [
                for (final v in update.variants)
                  {
                    'abi': v.abi,
                    'apk_url': v.apkUrl,
                    'sha256': v.sha256,
                    'size_bytes': v.sizeBytes,
                  },
              ],
            },
        },
      ),
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
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
