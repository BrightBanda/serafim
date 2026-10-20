import 'package:serafim/src/data/models/public_user.dart';

/// What a notification is about. Mirrors the backend's notification `type`.
enum NotificationKind {
  friendRequest,
  friendAccepted,
  newFollower,
  circleJoined,
  circleJoinRequest,
  circleRequestApproved,
  circleRequestRejected,
  circlePostCommented,
  circleCommentReplied,
  circleMention,
  circlePostPinned,
  circleRoleChanged,
  circleBanned,
  unknown;

  static NotificationKind parse(String? raw) => switch (raw) {
    'friend_request' => NotificationKind.friendRequest,
    'friend_accepted' => NotificationKind.friendAccepted,
    'new_follower' => NotificationKind.newFollower,
    'circle_joined' => NotificationKind.circleJoined,
    'circle_join_request' => NotificationKind.circleJoinRequest,
    'circle_request_approved' => NotificationKind.circleRequestApproved,
    'circle_request_rejected' => NotificationKind.circleRequestRejected,
    'circle_post_commented' => NotificationKind.circlePostCommented,
    'circle_comment_replied' => NotificationKind.circleCommentReplied,
    'circle_mention' => NotificationKind.circleMention,
    'circle_post_pinned' => NotificationKind.circlePostPinned,
    'circle_role_changed' => NotificationKind.circleRoleChanged,
    'circle_banned' => NotificationKind.circleBanned,
    _ => NotificationKind.unknown,
  };

  /// Whether this is about a Circle.
  bool get isCircle => name.startsWith('circle');

  /// What the other person did, after their name.
  String get action => switch (this) {
    NotificationKind.friendRequest => 'sent you a friend request',
    NotificationKind.friendAccepted => 'accepted your friend request',
    NotificationKind.newFollower => 'started following you',
    NotificationKind.circleJoined => 'joined your Circle',
    NotificationKind.circleJoinRequest => 'asked to join your Circle',
    NotificationKind.circleRequestApproved =>
      'approved your request to join their Circle',
    NotificationKind.circleRequestRejected =>
      'declined your request to join their Circle',
    NotificationKind.circlePostCommented => 'commented on your post',
    NotificationKind.circleCommentReplied => 'replied to your comment',
    NotificationKind.circleMention => 'mentioned you in a Circle',
    NotificationKind.circlePostPinned => 'pinned your post',
    NotificationKind.circleRoleChanged => 'changed your role in a Circle',
    NotificationKind.circleBanned => 'banned you from a Circle',
    NotificationKind.unknown => 'interacted with you',
  };

  /// One line saying what [name] did.
  String describe(String name) => '$name $action';

  /// Short label for the top-of-screen banner.
  String get bannerLabel => switch (this) {
    NotificationKind.friendRequest => 'FRIEND REQUEST',
    NotificationKind.friendAccepted => 'NEW FRIEND',
    NotificationKind.newFollower => 'NEW FOLLOWER',
    NotificationKind.unknown => 'NOTIFICATION',
    _ => 'CIRCLES',
  };
}

/// One entry on the notifications page (backend `NotificationResponse`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.isRead,
    required this.createdAt,
    required this.actor,
  });

  final String id;
  final NotificationKind kind;
  final bool isRead;
  final DateTime createdAt;

  /// Who did it.
  final PublicUser actor;

  String get text => kind.describe(actor.displayName);

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    kind: kind,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    actor: actor,
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      kind: NotificationKind.parse(json['type'] as String?),
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      actor: PublicUser.fromJson(json['actor'] as Map<String, dynamic>),
    );
  }
}
