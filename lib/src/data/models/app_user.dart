import 'package:serafim/src/data/models/profile.dart';

/// Mirrors the backend's `UserResponse` / `UserWithProfile`
/// (app/schemas/user.py).
///
/// This is the *application* user row, not the Supabase auth record: it shares
/// the same UUID but lives in our own `users` table and is created by
/// `POST /auth/sync`.
class AppUser {
  const AppUser({
    required this.id,
    required this.isActive,
    required this.createdAt,
    this.email,
    this.profile,
  });

  final String id;
  final String? email;
  final bool isActive;
  final DateTime createdAt;

  /// Only populated by `GET /auth/me`; `POST /auth/sync` omits it.
  final Profile? profile;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'];
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      profile: profile is Map<String, dynamic> ? Profile.fromJson(profile) : null,
    );
  }
}
