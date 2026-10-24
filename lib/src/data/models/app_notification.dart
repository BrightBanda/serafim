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
  circleNewPost,

  // About posts outside Circles, and Sparks anywhere.
  friendPosted,
  postCommented,
  commentReplied,
  postSparked,
  commentSparked,
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
    'circle_new_post' => NotificationKind.circleNewPost,
    'friend_posted' => NotificationKind.friendPosted,
    'post_commented' => NotificationKind.postCommented,
    'comment_replied' => NotificationKind.commentReplied,
    'post_sparked' => NotificationKind.postSparked,
    'comment_sparked' => NotificationKind.commentSparked,
    _ => NotificationKind.unknown,
  };

  /// Whether this is about a Circle.
  bool get isCircle => name.startsWith('circle');

  /// Whether it is about a post or comment (in a Circle or not), so opening
  /// it goes to that post.
  bool get isAboutPost => switch (this) {
    NotificationKind.friendPosted ||
    NotificationKind.circleNewPost ||
    NotificationKind.postCommented ||
    NotificationKind.circlePostCommented ||
    NotificationKind.commentReplied ||
    NotificationKind.circleCommentReplied ||
    NotificationKind.circleMention ||
    NotificationKind.circlePostPinned ||
    NotificationKind.postSparked ||
    NotificationKind.commentSparked => true,
    _ => false,
  };

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
    NotificationKind.circleNewPost => 'posted in a Circle you are in',
    NotificationKind.friendPosted => 'shared a new post',
    NotificationKind.postCommented => 'commented on your post',
    NotificationKind.commentReplied => 'replied to your comment',
    NotificationKind.postSparked => 'sparked your post',
    NotificationKind.commentSparked => 'sparked your comment',
    NotificationKind.unknown => 'interacted with you',
  };

  /// One line saying what [name] did.
  String describe(String name) => '$name $action';

  /// Short label for the top-of-screen banner.
  String get bannerLabel => switch (this) {
    NotificationKind.friendRequest => 'FRIEND REQUEST',
    NotificationKind.friendAccepted => 'NEW FRIEND',
    NotificationKind.newFollower => 'NEW FOLLOWER',
    NotificationKind.friendPosted => 'NEW POST',
    NotificationKind.postCommented ||
    NotificationKind.commentReplied => 'COMMENTS',
    NotificationKind.postSparked || NotificationKind.commentSparked => 'SPARKS',
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
    this.circleId,
    this.postId,
  });

  final String id;
  final NotificationKind kind;
  final bool isRead;
  final DateTime createdAt;

  /// Who did it.
  final PublicUser actor;

  /// The Circle a Circle notification is about, when the server says.
  final String? circleId;

  /// The post it is about (a comment, a reply, a mention, a pin), when the
  /// server says. Opening the notification goes straight to it.
  final String? postId;

  String get text => kind.describe(actor.displayName);

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    kind: kind,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    actor: actor,
    circleId: circleId,
    postId: postId,
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      kind: NotificationKind.parse(json['type'] as String?),
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      actor: PublicUser.fromJson(json['actor'] as Map<String, dynamic>),
      circleId: idIn(json, 'circle_id'),
      postId: idIn(json, 'post_id'),
    );
  }

  /// An id from a notification payload, at the top level or inside its
  /// `data` map; ids may arrive as strings or numbers.
  static String? idIn(Map<String, dynamic> json, String key) {
    final data = json['data'];
    final raw = json[key] ?? (data is Map ? data[key] : null);
    final id = raw?.toString();
    return id == null || id.isEmpty ? null : id;
  }
}
