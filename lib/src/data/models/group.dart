import 'package:serafim/src/data/models/public_user.dart';

enum GroupRole {
  owner,
  admin,
  member;

  static GroupRole parse(String? raw) => switch (raw) {
    'owner' => GroupRole.owner,
    'admin' => GroupRole.admin,
    _ => GroupRole.member,
  };

  String get label => switch (this) {
    GroupRole.owner => 'Owner',
    GroupRole.admin => 'Admin',
    GroupRole.member => 'Member',
  };

  /// Edit the name, photo and rules; remove members.
  bool get canManage => this == GroupRole.owner || this == GroupRole.admin;

  /// Mirrors the server: the owner removes anyone else, admins remove members.
  bool canRemove(GroupRole target) => switch (this) {
    GroupRole.owner => target != GroupRole.owner,
    GroupRole.admin => target == GroupRole.member,
    GroupRole.member => false,
  };
}

/// The room id a group's messages are stored under on the device.
String groupRoomId(String groupId) => 'group_$groupId';

bool isGroupRoom(String roomId) => roomId.startsWith('group_');

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// A group you are in (backend `GroupSummary`).
class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.myRole,
    required this.memberCount,
    required this.joinedAt,
    this.photoUrl,
    this.rulesUpdatedAt,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final GroupRole myRole;
  final int memberCount;
  final DateTime? rulesUpdatedAt;
  final DateTime joinedAt;

  String get roomId => groupRoomId(id);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'photo_url': photoUrl,
    'my_role': myRole.name,
    'member_count': memberCount,
    'rules_updated_at': rulesUpdatedAt?.toIso8601String(),
    'joined_at': joinedAt.toIso8601String(),
  };

  factory GroupSummary.fromJson(Map<String, dynamic> json) => GroupSummary(
    id: json['id'].toString(),
    name: json['name'] as String,
    photoUrl: json['photo_url'] as String?,
    myRole: GroupRole.parse(json['my_role'] as String?),
    memberCount: json['member_count'] as int? ?? 0,
    rulesUpdatedAt: _date(json['rules_updated_at']),
    joinedAt: _date(json['joined_at']) ?? DateTime.now().toUtc(),
  );
}

class GroupMemberInfo {
  const GroupMemberInfo({
    required this.user,
    required this.role,
    required this.joinedAt,
  });

  final PublicUser user;
  final GroupRole role;
  final DateTime joinedAt;

  factory GroupMemberInfo.fromJson(Map<String, dynamic> json) =>
      GroupMemberInfo(
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        role: GroupRole.parse(json['role'] as String?),
        joinedAt: _date(json['joined_at']) ?? DateTime.now().toUtc(),
      );
}

/// Everything about a group (backend `GroupDetail`), for members only.
class GroupDetail {
  const GroupDetail({
    required this.summary,
    required this.members,
    this.rules,
    this.ownerId,
  });

  final GroupSummary summary;
  final List<GroupMemberInfo> members;
  final String? rules;
  final String? ownerId;

  String get id => summary.id;

  GroupMemberInfo? member(String userId) {
    for (final m in members) {
      if (m.user.id == userId) return m;
    }
    return null;
  }

  factory GroupDetail.fromJson(Map<String, dynamic> json) => GroupDetail(
    summary: GroupSummary.fromJson(json),
    rules: json['rules'] as String?,
    ownerId: json['owner_id']?.toString(),
    members: [
      for (final m in (json['members'] as List? ?? const []))
        GroupMemberInfo.fromJson(m as Map<String, dynamic>),
    ],
  );
}

enum AddStatus { added, alreadyMember, blocked, notFound }

/// What happened to one person you tried to add.
class AddResult {
  const AddResult({
    required this.query,
    required this.status,
    required this.message,
    this.userId,
  });

  final String query;
  final AddStatus status;

  /// Says exactly what happened, e.g. "Sam only lets friends add them to
  /// groups."
  final String message;
  final String? userId;

  factory AddResult.fromJson(Map<String, dynamic> json) => AddResult(
    query: json['query'] as String? ?? '',
    status: switch (json['status']) {
      'added' => AddStatus.added,
      'already_member' => AddStatus.alreadyMember,
      'blocked' => AddStatus.blocked,
      _ => AddStatus.notFound,
    },
    message: json['message'] as String? ?? '',
    userId: json['user_id']?.toString(),
  );
}

/// Limits matching the server.
class GroupLimits {
  GroupLimits._();
  static const nameMax = 50;
  static const rulesMax = 2000;
}
