import 'package:serafim/src/data/models/public_user.dart';

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// Just enough of a Circle to label a post with it.
class CircleBrief {
  const CircleBrief({
    required this.id,
    required this.name,
    this.iconUrl,
    this.category,
  });

  final String id;
  final String name;
  final String? iconUrl;
  final String? category;

  factory CircleBrief.fromJson(Map<String, dynamic> json) => CircleBrief(
    id: json['id'].toString(),
    name: json['name'] as String,
    iconUrl: json['icon_url'] as String?,
    category: json['category'] as String?,
  );
}

/// A post. It belongs to a profile, or to a Circle.
class Post {
  const Post({
    required this.id,
    required this.author,
    required this.content,
    required this.createdAt,
    required this.sparkCount,
    required this.commentCount,
    required this.sparked,
    required this.pinned,
    this.circle,
    this.kind = 'text',
    this.imageUrls = const [],
    this.editedAt,
  });

  final String id;
  final PublicUser author;

  /// Pictures attached to the post, at most 4.
  final List<String> imageUrls;

  /// Set when the post is inside a Circle, so the app can show
  /// "Alex Banda · Flutter Developers".
  final CircleBrief? circle;
  final String content;
  final String kind;
  final int sparkCount;
  final int commentCount;

  /// Whether the signed-in person has sparked it.
  final bool sparked;
  final bool pinned;
  final DateTime createdAt;
  final DateTime? editedAt;

  bool get isInCircle => circle != null;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'].toString(),
    author: PublicUser.fromJson(json['author'] as Map<String, dynamic>),
    circle: json['circle'] == null
        ? null
        : CircleBrief.fromJson(json['circle'] as Map<String, dynamic>),
    content: json['content'] as String? ?? '',
    kind: json['kind'] as String? ?? 'text',
    imageUrls: [
      for (final u in (json['image_urls'] as List? ?? const [])) u as String,
    ],
    sparkCount: json['spark_count'] as int? ?? 0,
    commentCount: json['comment_count'] as int? ?? 0,
    sparked: json['sparked'] as bool? ?? false,
    pinned: json['pinned'] as bool? ?? false,
    createdAt: _date(json['created_at']) ?? DateTime.now().toUtc(),
    editedAt: _date(json['edited_at']),
  );
}

/// A comment on a post, or a reply to another comment.
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.content,
    required this.createdAt,
    required this.sparkCount,
    required this.sparked,
    this.parentId,
    this.editedAt,
  });

  final String id;
  final String postId;
  final PublicUser author;
  final String? parentId;
  final String content;
  final int sparkCount;
  final bool sparked;
  final DateTime createdAt;
  final DateTime? editedAt;

  bool get isReply => parentId != null;

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
    id: json['id'].toString(),
    postId: json['post_id'].toString(),
    author: PublicUser.fromJson(json['author'] as Map<String, dynamic>),
    parentId: json['parent_id']?.toString(),
    content: json['content'] as String? ?? '',
    sparkCount: json['spark_count'] as int? ?? 0,
    sparked: json['sparked'] as bool? ?? false,
    createdAt: _date(json['created_at']) ?? DateTime.now().toUtc(),
    editedAt: _date(json['edited_at']),
  );
}

/// A page of posts, with the cursor for the page after it.
class PostPage {
  const PostPage({required this.items, this.nextCursor});

  final List<Post> items;

  /// Null when there are no more.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory PostPage.fromJson(Map<String, dynamic> json) => PostPage(
    items: [
      for (final p in (json['items'] as List? ?? const []))
        Post.fromJson(p as Map<String, dynamic>),
    ],
    nextCursor: json['next_cursor'] as String?,
  );
}

/// The state after a Spark was added or removed.
class SparkResult {
  const SparkResult({
    required this.sparked,
    required this.sparkCount,
    this.postId,
    this.commentId,
  });

  final bool sparked;
  final int sparkCount;
  final String? postId;
  final String? commentId;

  factory SparkResult.fromJson(Map<String, dynamic> json) => SparkResult(
    sparked: json['sparked'] as bool? ?? false,
    sparkCount: json['spark_count'] as int? ?? 0,
    postId: json['post_id']?.toString(),
    commentId: json['comment_id']?.toString(),
  );
}

/// Limits matching the server.
class PostLimits {
  PostLimits._();
  static const contentMax = 2000;
  static const commentMax = 1000;
  static const imagesMax = 4;
  static const imageBytesMax = 2 * 1024 * 1024;
}
