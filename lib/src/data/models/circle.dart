import 'package:serafim/src/data/models/public_user.dart';

/// A Circle's role, for the signed-in person.
///
/// The three words are deliberately different from the chat group's
/// "admin" and from the backend's "Serafim admin": a Circle's Overseer is
/// neither. Do not rename them to "admin" — the admin dashboard brief
/// makes a point of keeping the three apart.
enum CircleRole {
  owner,
  overseer,
  member;

  static CircleRole parse(String? raw) => switch (raw) {
    'owner' => CircleRole.owner,
    'overseer' => CircleRole.overseer,
    _ => CircleRole.member,
  };

  String get label => switch (this) {
    CircleRole.owner => 'Owner',
    CircleRole.overseer => 'Overseer',
    CircleRole.member => 'Member',
  };

  /// Edit the Circle's details and rules, manage members, remove content,
  /// pin posts, approve join requests.
  bool get canManage => this == CircleRole.owner || this == CircleRole.overseer;

  /// Only the Owner may appoint Overseers, change the visibility, delete the
  /// Circle or hand it over.
  bool get isOwner => this == CircleRole.owner;

  /// Mirrors the server: the Owner removes anyone else, Overseers remove
  /// plain members.
  bool canRemove(CircleRole target) => switch (this) {
    CircleRole.owner => target != CircleRole.owner,
    CircleRole.overseer => target == CircleRole.member,
    CircleRole.member => false,
  };
}

/// Who can see a Circle and its posts.
enum CircleVisibility {
  public,
  private,
  inviteOnly;

  static CircleVisibility parse(String? raw) => switch (raw) {
    'private' => CircleVisibility.private,
    'invite_only' => CircleVisibility.inviteOnly,
    _ => CircleVisibility.public,
  };

  String get wire => switch (this) {
    CircleVisibility.public => 'public',
    CircleVisibility.private => 'private',
    CircleVisibility.inviteOnly => 'invite_only',
  };

  String get label => switch (this) {
    CircleVisibility.public => 'Public',
    CircleVisibility.private => 'Private',
    CircleVisibility.inviteOnly => 'Invite only',
  };

  String get blurb => switch (this) {
    CircleVisibility.public =>
      'Anyone can find this Circle, read its posts and join.',
    CircleVisibility.private =>
      'Anyone can find it, but only members can read the posts. You '
          'ask to join and an Overseer approves.',
    CircleVisibility.inviteOnly =>
      'Only people invited to this Circle can get in.',
  };
}

/// The nine interest categories, the same list the profile interests come
/// from (backend `app/core/interests.py`).
const circleCategories = <String>[
  'Sports',
  'Hobbies',
  'Entertainment',
  'Music',
  'Tech',
  'Creative',
  'Outdoors',
  'Food & drink',
  'Learning & life',
];

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// A Circle as a card (backend `CircleSummary`).
class CircleSummary {
  const CircleSummary({
    required this.id,
    required this.name,
    required this.visibility,
    required this.memberCount,
    required this.createdAt,
    this.description,
    this.category,
    this.iconUrl,
    this.myRole,
    this.joinedAt,
    this.myRequestPending = false,
    this.iAmBanned = false,
  });

  final String id;
  final String name;
  final String? description;
  final String? category;
  final String? iconUrl;
  final CircleVisibility visibility;
  final int memberCount;
  final DateTime createdAt;

  /// Null when the signed-in person is not a member.
  final CircleRole? myRole;
  final DateTime? joinedAt;

  /// True when a request to join is waiting to be approved.
  final bool myRequestPending;

  /// True when the Circle has banned this person.
  final bool iAmBanned;

  bool get isMember => myRole != null;

  /// The label on the button: Join, Request to join, or Open.
  String get joinLabel => switch (visibility) {
    CircleVisibility.public => 'Join',
    CircleVisibility.private =>
      myRequestPending ? 'Requested' : 'Request to join',
    CircleVisibility.inviteOnly => 'Invite only',
  };

  factory CircleSummary.fromJson(Map<String, dynamic> json) => CircleSummary(
    id: json['id'].toString(),
    name: json['name'] as String,
    description: json['description'] as String?,
    category: json['category'] as String?,
    iconUrl: json['icon_url'] as String?,
    visibility: CircleVisibility.parse(json['visibility'] as String?),
    memberCount: json['member_count'] as int? ?? 0,
    createdAt: _date(json['created_at']) ?? DateTime.now().toUtc(),
    myRole: json['my_role'] == null
        ? null
        : CircleRole.parse(json['my_role'] as String?),
    joinedAt: _date(json['joined_at']),
    myRequestPending: json['my_request_pending'] as bool? ?? false,
    iAmBanned: json['i_am_banned'] as bool? ?? false,
  );
}

/// One person in a Circle.
class CircleMemberInfo {
  const CircleMemberInfo({
    required this.user,
    required this.role,
    required this.joinedAt,
  });

  final PublicUser user;
  final CircleRole role;
  final DateTime joinedAt;

  factory CircleMemberInfo.fromJson(Map<String, dynamic> json) =>
      CircleMemberInfo(
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        role: CircleRole.parse(json['role'] as String?),
        joinedAt: _date(json['joined_at']) ?? DateTime.now().toUtc(),
      );
}

/// Someone waiting to join a private Circle.
class CircleJoinRequest {
  const CircleJoinRequest({
    required this.id,
    required this.user,
    required this.createdAt,
    this.message,
  });

  final String id;
  final PublicUser user;
  final String? message;
  final DateTime createdAt;

  factory CircleJoinRequest.fromJson(Map<String, dynamic> json) =>
      CircleJoinRequest(
        id: json['id'].toString(),
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        message: json['message'] as String?,
        createdAt: _date(json['created_at']) ?? DateTime.now().toUtc(),
      );
}

/// Everything about a Circle (backend `CircleDetail`).
class CircleDetail {
  const CircleDetail({
    required this.summary,
    required this.members,
    required this.postingEnabled,
    this.rules,
    this.bannerUrl,
    this.ownerId,
    this.pendingRequests = const [],
  });

  final CircleSummary summary;
  final List<CircleMemberInfo> members;
  final List<CircleJoinRequest> pendingRequests;
  final String? rules;
  final String? bannerUrl;
  final String? ownerId;
  final bool postingEnabled;

  String get id => summary.id;
  String get name => summary.name;
  CircleRole? get myRole => summary.myRole;
  bool get isMember => summary.isMember;

  CircleMemberInfo? member(String userId) {
    for (final m in members) {
      if (m.user.id == userId) return m;
    }
    return null;
  }

  factory CircleDetail.fromJson(Map<String, dynamic> json) => CircleDetail(
    summary: CircleSummary.fromJson(json),
    rules: json['rules'] as String?,
    bannerUrl: json['banner_url'] as String?,
    ownerId: json['owner_id']?.toString(),
    postingEnabled: json['posting_enabled'] as bool? ?? true,
    members: [
      for (final m in (json['members'] as List? ?? const []))
        CircleMemberInfo.fromJson(m as Map<String, dynamic>),
    ],
    pendingRequests: [
      for (final r in (json['pending_requests'] as List? ?? const []))
        CircleJoinRequest.fromJson(r as Map<String, dynamic>),
    ],
  );
}

/// What leaving a Circle did (backend `LeaveResult`).
class CircleLeaveResult {
  const CircleLeaveResult({
    required this.circleId,
    required this.left,
    this.circleDeleted = false,
    this.newOwnerId,
  });

  final String circleId;
  final bool left;

  /// True when the person was the last member, so the Circle went with them.
  final bool circleDeleted;

  /// Who the Circle passed to, if the person was its owner.
  final String? newOwnerId;

  factory CircleLeaveResult.fromJson(Map<String, dynamic> json) =>
      CircleLeaveResult(
        circleId: json['circle_id'].toString(),
        left: json['left'] as bool? ?? true,
        circleDeleted: json['circle_deleted'] as bool? ?? false,
        newOwnerId: json['new_owner_id']?.toString(),
      );
}

/// Limits matching the server.
class CircleLimits {
  CircleLimits._();
  static const nameMax = 50;
  static const descriptionMax = 1000;
  static const rulesMax = 2000;
}
