import 'package:serafim/src/data/models/public_user.dart';

/// What a notification is about. Mirrors the backend's notification `type`.
enum NotificationKind {
  friendRequest,
  friendAccepted,
  newFollower,
  unknown;

  static NotificationKind parse(String? raw) => switch (raw) {
    'friend_request' => NotificationKind.friendRequest,
    'friend_accepted' => NotificationKind.friendAccepted,
    'new_follower' => NotificationKind.newFollower,
    _ => NotificationKind.unknown,
  };

  /// What the other person did, after their name.
  String get action => switch (this) {
    NotificationKind.friendRequest => 'sent you a friend request',
    NotificationKind.friendAccepted => 'accepted your friend request',
    NotificationKind.newFollower => 'started following you',
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
