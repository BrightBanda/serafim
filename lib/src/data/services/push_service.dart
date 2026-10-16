import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// Tells the Serafim backend which phones to push to (`/devices`).
class PushService {
  const PushService(this._dio);

  final Dio _dio;

  /// Registers (or re-registers) an FCM token for the signed-in user. Safe to
  /// repeat: the backend upserts by token, and moves a token to the current
  /// user if a previous account on this phone had it.
  Future<void> registerDevice({
    required String token,
    required String platform,
    required bool showPreview,
  }) async {
    try {
      await _dio.post<dynamic>(
        '/devices',
        data: {
          'token': token,
          'platform': platform,
          'show_preview': showPreview,
        },
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Stops pushes to [token]. Only removes the caller's own registration.
  Future<void> unregisterDevice(String token) async {
    try {
      await _dio.delete<dynamic>('/devices', data: {'token': token});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
