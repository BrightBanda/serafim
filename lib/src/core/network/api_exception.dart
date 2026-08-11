import 'package:dio/dio.dart';

/// A transport-agnostic failure.
///
/// Services translate every [DioException] into one of these so that nothing
/// above the data layer needs to import dio. View models catch [ApiException]
/// and turn [message] straight into UI text.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  /// Message safe to show to a user.
  final String message;

  /// HTTP status, when the request reached the server.
  final int? statusCode;

  /// Machine-readable error code from the server, when it sent one.
  final String? code;

  /// True when the caller's token was rejected.
  bool get isUnauthorized => statusCode == 401;

  /// True when the resource does not exist — used by the profile view model to
  /// tell "no profile yet" apart from a real failure.
  bool get isNotFound => statusCode == 404;

  /// Maps a dio failure onto an [ApiException].
  ///
  /// Both backends report errors differently: FastAPI uses `{"detail": ...}`
  /// and Supabase GoTrue uses `{"msg"|"error_description"|"error": ...}`, so we
  /// probe for each in turn before falling back to a generic message.
  factory ApiException.fromDio(DioException error) {
    final response = error.response;

    if (response != null) {
      return ApiException(
        _messageFromBody(response.data) ?? _messageForStatus(response.statusCode),
        statusCode: response.statusCode,
        code: _codeFromBody(response.data),
      );
    }

    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The server took too long to respond.',
      DioExceptionType.connectionError =>
        'Could not reach the server. Check your connection.',
      DioExceptionType.cancel => 'Request cancelled.',
      DioExceptionType.badCertificate => 'The server certificate was rejected.',
      _ => 'Something went wrong. Please try again.',
    };

    return ApiException(message);
  }

  static String? _messageFromBody(Object? data) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is! Map) return null;

    for (final key in const ['detail', 'msg', 'error_description', 'message', 'error']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value;
      // FastAPI validation errors come back as a list of {loc, msg, type}.
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is Map && first['msg'] is String) return first['msg'] as String;
      }
    }
    return null;
  }

  static String? _codeFromBody(Object? data) {
    if (data is! Map) return null;
    final code = data['error_code'] ?? data['code'];
    return code is String ? code : null;
  }

  static String _messageForStatus(int? status) => switch (status) {
    400 => 'That request was rejected.',
    401 => 'Your session has expired. Please sign in again.',
    403 => 'You do not have access to that.',
    404 => 'Not found.',
    409 => 'That already exists.',
    422 => 'Some of the details you entered are invalid.',
    429 => 'Too many attempts. Try again in a moment.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'ApiException($statusCode): $message';
}
