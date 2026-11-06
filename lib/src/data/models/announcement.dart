import 'package:serafim/src/data/models/app_update.dart';

/// What the server stores as the text of a video with no words of its own, for
/// notifications and older apps. Not shown under the video.
const videoOnlyAnnouncementText = '🎬 A video from SERAFIM';

/// The video on an announcement. It stays on the server until the announcement
/// is deleted; the file itself is fetched only when someone taps it.
class AnnouncementVideo {
  const AnnouncementVideo({
    required this.name,
    required this.contentType,
    required this.size,
    this.durationMs = 0,
    this.thumbnail,
  });

  final String name;
  final String contentType;
  final int size;
  final int durationMs;

  /// A small JPEG, base64, exactly as the server sends it.
  final String? thumbnail;

  factory AnnouncementVideo.fromJson(Map<String, dynamic> json) =>
      AnnouncementVideo(
        name: json['name'] as String? ?? 'Video',
        contentType: json['content_type'] as String? ?? 'video/mp4',
        size: (json['size'] as num?)?.toInt() ?? 0,
        durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
        thumbnail: json['thumbnail'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'content_type': contentType,
    'size': size,
    'duration_ms': durationMs,
    'thumbnail': thumbnail,
  };
}

/// A message in the official SERAFIM chat (backend `AnnouncementResponse`).
class Announcement {
  const Announcement({
    required this.id,
    required this.content,
    required this.createdAt,
    this.update,
    this.video,
  });

  final String id;

  /// A video to go with the words, if any.
  final AnnouncementVideo? video;

  /// The words to show: a video's placeholder text is not shown under it.
  String get caption =>
      video != null && content == videoOnlyAnnouncementText ? '' : content;

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
    if (video != null) 'video': video!.toJson(),
  };

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'].toString(),
    content: json['content'] as String? ?? '',
    createdAt: _parseUtc(json['created_at'] as String),
    // Unknown kinds are just text; a malformed update degrades to its text.
    update: json['kind'] == 'app_update'
        ? AppUpdate.tryParse(json['update'])
        : null,
    video: json['video'] is Map<String, dynamic>
        ? AnnouncementVideo.fromJson(json['video'] as Map<String, dynamic>)
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
