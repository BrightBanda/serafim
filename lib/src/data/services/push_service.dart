import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// What the server reports after a test notification.
class PushTestResult {
  const PushTestResult({
    required this.ok,
    required this.devices,
    required this.accepted,
    this.reason,
  });

  final bool ok;
  final int devices;
  final int accepted;

  /// Why it failed, in words fit for the screen.
  final String? reason;

  factory PushTestResult.fromJson(Map<String, dynamic> json) => PushTestResult(
    ok: json['ok'] as bool? ?? false,
    devices: json['devices'] as int? ?? 0,
    accepted: json['accepted'] as int? ?? 0,
    reason: json['reason'] as String?,
  );
}

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

  /// `POST /devices/test` — asks the server to push a test notification to
  /// this account's registered phones, and report what happened.
  Future<PushTestResult> sendTest() async {
    try {
      final response = await _dio.post<dynamic>('/devices/test');
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Something went wrong. Please try again.');
      }
      return PushTestResult.fromJson(data);
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
