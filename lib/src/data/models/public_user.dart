/// Where this person stands relative to the signed-in user. Mirrors the
/// backend's `friend_status`.
enum FriendStatus {
  none,
  friends,
  requestSent,
  requestReceived;

  static FriendStatus parse(String? raw) => switch (raw) {
    'friends' => FriendStatus.friends,
    'request_sent' => FriendStatus.requestSent,
    'request_received' => FriendStatus.requestReceived,
    _ => FriendStatus.none,
  };
}

/// What one signed-in user may see of another (backend `PublicUser`). There is
/// deliberately no email here.
class PublicUser {
  const PublicUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.profilePic,
    this.interests = const [],
    this.sharedInterests = const [],
    this.friendStatus = FriendStatus.none,
    this.isFollowing = false,
    this.followsYou = false,
    this.acceptsFriendRequests = true,
    this.followerCount,
    this.followingCount,
  });

  final String id;
  final String username;
  final String displayName;
  final String? profilePic;
  final List<String> interests;

  /// Interests both people listed — the only basis for a "why am I seeing
  /// this person" reason.
  final List<String> sharedInterests;
  final FriendStatus friendStatus;

  /// You follow them / they follow you. Independent of friendship.
  final bool isFollowing;
  final bool followsYou;

  /// False when they have turned friend requests off.
  final bool acceptsFriendRequests;

  /// Only present on a single-profile lookup.
  final int? followerCount;
  final int? followingCount;

  bool get isFriend => friendStatus == FriendStatus.friends;

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? value.map((e) => e.toString()).toList(growable: false)
        : const [];

    return PublicUser(
      id: json['id'].toString(),
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      profilePic: json['profile_pic'] as String?,
      interests: strings(json['interests']),
      sharedInterests: strings(json['shared_interests']),
      friendStatus: FriendStatus.parse(json['friend_status'] as String?),
      isFollowing: json['is_following'] as bool? ?? false,
      followsYou: json['follows_you'] as bool? ?? false,
      acceptsFriendRequests: json['accepts_friend_requests'] as bool? ?? true,
      followerCount: json['follower_count'] as int?,
      followingCount: json['following_count'] as int?,
    );
  }
}

class FriendRequests {
  const FriendRequests({this.incoming = const [], this.outgoing = const []});

  final List<PublicUser> incoming;
  final List<PublicUser> outgoing;
}

/// Human wording for why someone appears in Discover. Returns null when there
/// is nothing real to say — never a made-up reason.
String? discoverReason(List<String> sharedInterests) {
  if (sharedInterests.isEmpty) return null;
  if (sharedInterests.length == 1) {
    return 'Also interested in ${sharedInterests.first}';
  }
  final shown = sharedInterests.take(3).toList();
  final extra = sharedInterests.length - shown.length;
  final head = shown.length == 2
      ? '${shown[0]} and ${shown[1]}'
      : '${shown[0]}, ${shown[1]} and ${shown[2]}';
  return extra > 0
      ? 'Shares your interests: $head +$extra more'
      : 'Shares your interests: $head';
}
