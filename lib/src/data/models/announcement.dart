import 'package:serafim/src/data/models/app_update.dart';

/// A message in the official SERAFIM chat (backend `AnnouncementResponse`).
class Announcement {
  const Announcement({
    required this.id,
    required this.content,
    required this.createdAt,
    this.update,
  });

  final String id;

  /// Plain text. For an app update, a readable fallback (what older app
  /// versions show).
  final String content;
  final DateTime createdAt;

  /// Set when this announces an Android release (kind `app_update`).
  final AppUpdate? update;

  /// What the chat list and banners show.
  String get preview => update != null
      ? '⬆️ Serafim ${update!.versionName} is available'
      : content;

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (update != null) 'kind': 'app_update',
    if (update != null) 'update': update!.toJson(),
  };

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'].toString(),
    content: json['content'] as String? ?? '',
    createdAt: _parseUtc(json['created_at'] as String),
    // Unknown kinds are just text; a malformed update degrades to its text.
    update: json['kind'] == 'app_update'
        ? AppUpdate.tryParse(json['update'])
        : null,
  );

  // The server sends UTC; an offset-less timestamp is UTC too.
  static DateTime _parseUtc(String raw) {
    final hasOffset =
        raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
    return DateTime.parse(hasOffset ? raw : '${raw}Z').toUtc();
  }
}

/// How the official chat looks for the signed-in user (backend
/// `OfficialChatInfo`).
class OfficialChatInfo {
  const OfficialChatInfo({
    required this.name,
    required this.username,
    required this.canPost,
    this.latest,
  });

  final String name;
  final String username;

  /// Whether this user is an administrator allowed to post. Decided by the
  /// server; the app only uses it to show or hide the composer.
  final bool canPost;
  final Announcement? latest;

  factory OfficialChatInfo.fromJson(Map<String, dynamic> json) =>
      OfficialChatInfo(
        name: json['name'] as String? ?? 'SERAFIM',
        username: json['username'] as String? ?? 'serafim',
        canPost: json['can_post'] as bool? ?? false,
        latest: json['latest'] is Map<String, dynamic>
            ? Announcement.fromJson(json['latest'] as Map<String, dynamic>)
            : null,
      );
}
