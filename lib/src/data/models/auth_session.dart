/// A Supabase auth session — the tokens plus the identity they belong to.
///
/// Hand-written JSON, no code generation. The field names on the wire are
/// GoTrue's snake_case; the Dart side stays camelCase.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    this.email,
  });

  final String accessToken;
  final String refreshToken;

  /// Absolute expiry of [accessToken], in UTC.
  final DateTime expiresAt;

  /// `auth.users.id` — the same UUID the backend stores as `users.id`.
  final String userId;
  final String? email;

  /// Parses a GoTrue token response (`/signup`, `/token`).
  ///
  /// `expires_at` is a unix timestamp and is not always present, so we fall
  /// back to `expires_in` measured from now.
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final userId = user is Map ? user['id'] : null;
    if (userId is! String) {
      throw const FormatException('Auth response did not contain a user id.');
    }

    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: _expiryFrom(json),
      userId: userId,
      email: user is Map && user['email'] is String ? user['email'] as String : null,
    );
  }

  /// Restores a session previously written by [toJson].
  factory AuthSession.fromStorage(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      userId: json['userId'] as String,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'userId': userId,
    'email': email,
  };

  static DateTime _expiryFrom(Map<String, dynamic> json) {
    final expiresAt = json['expires_at'];
    if (expiresAt is int) {
      return DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true);
    }
    final expiresIn = json['expires_in'];
    final seconds = expiresIn is int ? expiresIn : 3600;
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }

  /// Treats the token as expired 30s early so a request never leaves with a
  /// token that dies in flight.
  bool get isExpired =>
      DateTime.now().toUtc().isAfter(expiresAt.subtract(const Duration(seconds: 30)));

  AuthSession copyWith({String? accessToken, String? refreshToken, DateTime? expiresAt}) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      userId: userId,
      email: email,
    );
  }
}
