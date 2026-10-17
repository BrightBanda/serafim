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
        _messageFromBody(response.data) ??
            _messageForStatus(response.statusCode),
        statusCode: response.statusCode,
        code: _codeFromBody(response.data),
      );
    }

    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The server is taking too long to respond. It may be waking up, so '
            'try again in a moment.',
      DioExceptionType.connectionError =>
        "Can't reach the server. Check your internet connection and try "
            'again.',
      DioExceptionType.cancel => 'Request cancelled.',
      DioExceptionType.badCertificate => 'The server certificate was rejected.',
      _ => 'Something went wrong. Please try again.',
    };

    return ApiException(message);
  }

  static String? _messageFromBody(Object? data) {
    final code = _codeFromBody(data);
    final known = code == null ? null : _messageForCode(code);
    if (known != null) return known;

    String? raw;
    if (data is String) {
      raw = data;
    } else if (data is Map) {
      for (final key in const [
        'detail',
        'msg',
        'error_description',
        'message',
        'error',
      ]) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          raw = value;
          break;
        }
        // FastAPI validation errors come back as a list of {loc, msg, type}.
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          if (first is Map && first['msg'] is String) {
            raw = first['msg'] as String;
            break;
          }
        }
      }
    }
    return raw == null ? null : _tidy(raw);
  }

  /// Friendly wording for the error codes Supabase and our backend send.
  static String? _messageForCode(String code) => switch (code) {
    'invalid_credentials' => 'That email or password is incorrect.',
    'user_already_exists' || 'email_exists' =>
      'An account with that email already exists. Try logging in instead.',
    'email_not_confirmed' =>
      'Please confirm your email first. Check your inbox for the link.',
    'weak_password' =>
      'That password is too weak. Use a longer one with a mix of letters '
          'and numbers.',
    'over_request_rate_limit' ||
    'over_email_send_rate_limit' ||
    'over_sms_send_rate_limit' =>
      'Too many attempts. Please wait a minute and try again.',
    'user_banned' => 'This account has been suspended.',
    'signup_disabled' => 'Sign-ups are switched off right now.',
    'provider_disabled' || 'oauth_provider_not_supported' =>
      "Google sign-in isn't switched on for this app yet.",
    'bad_jwt' ||
    'session_expired' ||
    'session_not_found' ||
    'refresh_token_not_found' =>
      'Your session has expired. Please sign in again.',
    _ => null,
  };

  /// Turns a server message into something a person can read: strips
  /// framework prefixes, rewrites known technical phrases, and refuses to show
  /// HTML pages or stack traces.
  static String? _tidy(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    final lower = text.toLowerCase();
    // Addresses, hosts and IPs mean nothing to a person and say too much about
    // our setup, so a message carrying one is replaced by the generic wording.
    if (RegExp(r'https?://|wss?://|www\.|\b[\w-]+\.(supabase|onrender|herokuapp|railway|fly|vercel)\.\w+|\b\d{1,3}(\.\d{1,3}){3}\b').hasMatch(lower)) {
      return null;
    }
    if (lower.startsWith('<') ||
        lower.contains('<html') ||
        lower.contains('traceback')) {
      return null; // an error page, not a message
    }
    if (lower.contains('invalid or missing access token')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (lower.contains('provider is not enabled') ||
        lower.contains('unsupported provider')) {
      return "Google sign-in isn't switched on for this app yet.";
    }
    if (lower.contains('id token') &&
        (lower.contains('invalid') ||
            lower.contains('bad') ||
            lower.contains('nonce'))) {
      return "Google couldn't verify your sign-in. Please try again.";
    }
    if (lower.contains('row-level security') || lower.contains('row level security')) {
      return "You don't have permission to upload that. Try signing out and back in.";
    }
    if (lower.contains('bucket not found')) {
      return "Photo storage isn't set up yet. Please try again later.";
    }
    if (lower.contains('payload too large') || lower.contains('maximum allowed size')) {
      return 'That file is too large.';
    }
    if (lower.contains('mime type') && lower.contains('not supported')) {
      return "That kind of file can't be used here. Try a JPG or PNG photo.";
    }
    if (lower.contains('username already taken')) {
      return 'That username is already taken. Try another one.';
    }
    if (lower.contains('invalid login credentials')) {
      return 'That email or password is incorrect.';
    }
    if (lower.contains('user already registered')) {
      return 'An account with that email already exists. Try logging in instead.';
    }

    // "Value error, Username must be..." -> "Username must be..."
    text = text.replaceFirst(
      RegExp(r'^(value error|assertion error),\s*', caseSensitive: false),
      '',
    );
    if (text.length > 220) return null; // too long to be meant for a person

    // Messages should read as sentences.
    text = text[0].toUpperCase() + text.substring(1);
    if (!RegExp(r'[.!?]$').hasMatch(text)) text = '$text.';
    return text;
  }

  static String? _codeFromBody(Object? data) {
    if (data is! Map) return null;
    final code = data['error_code'] ?? data['code'];
    return code is String ? code : null;
  }

  static String _messageForStatus(int? status) => switch (status) {
    400 => "That didn't go through. Please check what you entered.",
    401 => 'Your session has expired. Please sign in again.',
    403 => "You don't have permission to do that.",
    404 => "We couldn't find that.",
    409 => 'That already exists.',
    413 => 'That file is too large.',
    422 => 'Some of the details you entered are not valid.',
    429 => 'Too many attempts. Please wait a minute and try again.',
    500 => 'The server ran into a problem. Please try again.',
    502 || 503 || 504 =>
      'The server is temporarily unavailable. It may be waking up, so try '
          'again in a moment.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'ApiException($statusCode): $message';
}
