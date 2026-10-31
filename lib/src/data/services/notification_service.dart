import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_notification.dart';

/// Talks to the backend's `/notifications` routes. Every route is scoped to
/// the signed-in user by the bearer token.
class NotificationService {
  const NotificationService(this._dio);

  final Dio _dio;

  /// Newest first.
  Future<List<AppNotification>> list({int limit = 50}) async {
    final data = await _call(
      () => _dio.get<dynamic>(
        '/notifications',
        queryParameters: {'limit': limit},
      ),
    );
    if (data is! List) {
      throw const ApiException('Something went wrong. Please try again.');
    }
    return [
      for (final json in data)
        AppNotification.fromJson(json as Map<String, dynamic>),
    ];
  }

  /// Marks [ids] read, or every notification when [ids] is null.
  Future<void> markRead({List<String>? ids}) async {
    await _call(
      () => _dio.post<dynamic>('/notifications/read', data: {'ids': ids}),
    );
  }

  Future<void> delete(String id) async {
    await _call(() => _dio.delete<dynamic>('/notifications/$id'));
  }

  Future<Object?> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
