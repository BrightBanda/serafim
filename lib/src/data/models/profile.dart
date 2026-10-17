/// Who may add someone to group chats. Enforced by the server.
enum GroupAddPrivacy {
  everyone('Everyone', 'Anyone can add you to a group.'),
  friends('Friends only', 'Only your friends can add you.'),
  nobody('Nobody', 'No one can add you to a group.');

  const GroupAddPrivacy(this.label, this.description);

  final String label;
  final String description;

  static GroupAddPrivacy parse(String? raw) => GroupAddPrivacy.values
      .firstWhere((v) => v.name == raw, orElse: () => GroupAddPrivacy.everyone);
}

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
    this.allowFriendRequests = true,
    this.bio,
    this.lockProfile = false,
    this.groupAddPrivacy = GroupAddPrivacy.everyone,
  });

  final String userId;

  /// Privacy: who may add this user to groups.
  final GroupAddPrivacy groupAddPrivacy;

  /// Privacy: when false, nobody can send this user a friend request.
  final bool allowFriendRequests;

  /// Privacy: when true, other people cannot see this user's friends,
  /// followers or following.
  final bool lockProfile;

  /// A short self-description, or null when there is none.
  final String? bio;
  final String displayName;
  final String username;
  final String? profilePic;
  final List<String> interests;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'display_name': displayName,
    'username': username,
    'profile_pic': profilePic,
    'interests': interests,
    'allow_friend_requests': allowFriendRequests,
    'bio': bio,
    'lock_profile': lockProfile,
    'group_add_privacy': groupAddPrivacy.name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

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
      allowFriendRequests: json['allow_friend_requests'] as bool? ?? true,
      bio: json['bio'] as String?,
      lockProfile: json['lock_profile'] as bool? ?? false,
      groupAddPrivacy: GroupAddPrivacy.parse(
        json['group_add_privacy'] as String?,
      ),
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
    this.allowFriendRequests,
    this.bio,
    this.lockProfile,
    this.groupAddPrivacy,
  });

  final GroupAddPrivacy? groupAddPrivacy;
  final String? displayName;
  final String? username;
  final String? profilePic;
  final List<String>? interests;
  final bool? allowFriendRequests;

  /// An empty string clears the bio; null leaves it alone.
  final String? bio;
  final bool? lockProfile;

  Map<String, dynamic> toJson() => {
    if (displayName != null) 'display_name': displayName,
    if (username != null) 'username': username,
    if (profilePic != null) 'profile_pic': profilePic,
    if (interests != null) 'interests': interests,
    if (allowFriendRequests != null)
      'allow_friend_requests': allowFriendRequests,
    if (bio != null) 'bio': bio,
    if (lockProfile != null) 'lock_profile': lockProfile,
    if (groupAddPrivacy != null) 'group_add_privacy': groupAddPrivacy!.name,
  };

  bool get isEmpty => toJson().isEmpty;
}
