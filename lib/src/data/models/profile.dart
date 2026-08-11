/// Mirrors the backend's `ProfileResponse` (app/schemas/profile.py).
class Profile {
  const Profile({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.createdAt,
    required this.updatedAt,
    this.profilePic,
    this.interests = const [],
  });

  final String userId;
  final String displayName;
  final String username;
  final String? profilePic;
  final List<String> interests;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final interests = json['interests'];
    return Profile(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      username: json['username'] as String,
      profilePic: json['profile_pic'] as String?,
      interests: interests is List
          ? interests.map((e) => e.toString()).toList(growable: false)
          : const [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Body for `POST /profile/me`. Every field the backend requires is required
/// here too, so an invalid create request cannot be constructed.
class ProfileCreateRequest {
  const ProfileCreateRequest({
    required this.displayName,
    required this.username,
    this.profilePic,
    this.interests,
  });

  final String displayName;
  final String username;
  final String? profilePic;
  final List<String>? interests;

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'username': username,
    if (profilePic != null) 'profile_pic': profilePic,
    if (interests != null) 'interests': interests,
  };
}

/// Body for `PUT /profile/me`.
///
/// The backend applies only non-null fields, so omitting a key leaves it
/// untouched — we drop nulls rather than sending them.
class ProfileUpdateRequest {
  const ProfileUpdateRequest({
    this.displayName,
    this.username,
    this.profilePic,
    this.interests,
  });

  final String? displayName;
  final String? username;
  final String? profilePic;
  final List<String>? interests;

  Map<String, dynamic> toJson() => {
    if (displayName != null) 'display_name': displayName,
    if (username != null) 'username': username,
    if (profilePic != null) 'profile_pic': profilePic,
    if (interests != null) 'interests': interests,
  };

  bool get isEmpty => toJson().isEmpty;
}
