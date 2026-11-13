import 'dart:convert';
import 'dart:typed_data';

enum MomentKind { photo, video }

/// Who may see a moment.
enum MomentAudience {
  /// Everyone on Serafim.
  everyone,

  /// Friends only.
  friends,

  /// Friends, apart from the ones left out.
  except;

  /// What the server calls it.
  String get wire => this == everyone ? 'public' : name;

  static MomentAudience fromWire(String? value) => switch (value) {
    'public' => everyone,
    'except' => except,
    _ => friends,
  };
}

/// A photo or video with a caption, shown for 24 hours.
class Moment {
  const Moment({
    required this.id,
    required this.userId,
    required this.kind,
    required this.audience,
    required this.durationMs,
    required this.createdAt,
    required this.expiresAt,
    required this.thumbnail,
    required this.seen,
    required this.liked,
    required this.likeCount,
    this.caption,
    this.allowSave = true,
    this.viewCount,
    this.excludeIds,
  });

  factory Moment.fromJson(Map<String, dynamic> json) => Moment(
    id: json['id'].toString(),
    userId: json['user_id'].toString(),
    kind: json['kind'] == 'video' ? MomentKind.video : MomentKind.photo,
    caption: json['caption'] as String?,
    audience: MomentAudience.fromWire(json['visibility'] as String?),
    allowSave: json['allow_save'] as bool? ?? true,
    durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    thumbnail: base64Decode(json['thumbnail'] as String),
    seen: json['seen'] as bool? ?? false,
    liked: json['liked'] as bool? ?? false,
    likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
    viewCount: (json['view_count'] as num?)?.toInt(),
    excludeIds: (json['exclude_ids'] as List?)
        ?.map((e) => e.toString())
        .toList(),
  );

  final String id;
  final String userId;
  final MomentKind kind;
  final String? caption;
  final MomentAudience audience;

  /// Whether people may save it (the owner can switch it off).
  final bool allowSave;
  final int durationMs;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// A small JPEG: shown while the picture or video loads.
  final Uint8List thumbnail;
  final bool seen;
  final bool liked;
  final int likeCount;

  /// Only on your own moments.
  final int? viewCount;
  final List<String>? excludeIds;

  bool get isVideo => kind == MomentKind.video;

  /// How long it has left, rounded down to whole minutes.
  Duration timeLeft([DateTime? now]) {
    final left = expiresAt.difference((now ?? DateTime.now()).toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  Moment copyWith({bool? seen, bool? liked, int? likeCount}) => Moment(
    id: id,
    userId: userId,
    kind: kind,
    caption: caption,
    audience: audience,
    allowSave: allowSave,
    durationMs: durationMs,
    createdAt: createdAt,
    expiresAt: expiresAt,
    thumbnail: thumbnail,
    seen: seen ?? this.seen,
    liked: liked ?? this.liked,
    likeCount: likeCount ?? this.likeCount,
    viewCount: viewCount,
    excludeIds: excludeIds,
  );
}

/// Someone who has a moment showing (that you may see), for the ring round
/// their picture.
class MomentRing {
  const MomentRing({
    required this.userId,
    required this.count,
    required this.latestAt,
    required this.allSeen,
  });

  factory MomentRing.fromJson(Map<String, dynamic> json) => MomentRing(
    userId: json['user_id'].toString(),
    count: (json['count'] as num).toInt(),
    latestAt: DateTime.parse(json['latest_at'] as String).toUtc(),
    allSeen: json['all_seen'] as bool? ?? false,
  );

  final String userId;
  final int count;
  final DateTime latestAt;

  /// You have looked at everything they have showing.
  final bool allSeen;

  MomentRing seen() => MomentRing(
    userId: userId,
    count: count,
    latestAt: latestAt,
    allSeen: true,
  );
}

/// One person who looked at your moment.
class MomentViewer {
  const MomentViewer({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.viewedAt,
    required this.liked,
    this.profilePic,
  });

  factory MomentViewer.fromJson(Map<String, dynamic> json) {
    final person = json['person'] as Map<String, dynamic>;
    return MomentViewer(
      userId: person['id'].toString(),
      username: person['username'] as String,
      displayName: person['display_name'] as String,
      profilePic: person['profile_pic'] as String?,
      viewedAt: DateTime.parse(json['viewed_at'] as String).toUtc(),
      liked: json['liked'] as bool? ?? false,
    );
  }

  final String userId;
  final String username;
  final String displayName;
  final String? profilePic;
  final DateTime viewedAt;
  final bool liked;
}

class MomentViewers {
  const MomentViewers({required this.viewers, required this.likeCount});

  factory MomentViewers.fromJson(Map<String, dynamic> json) => MomentViewers(
    viewers: (json['viewers'] as List)
        .map((v) => MomentViewer.fromJson(v as Map<String, dynamic>))
        .toList(),
    likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
  );

  final List<MomentViewer> viewers;
  final int likeCount;
}

/// What a chat message that answers a moment carries, so the reply can show
/// what it was about even after the moment has ended.
class MomentPreview {
  const MomentPreview({
    required this.id,
    required this.kind,
    required this.thumbnail,
    this.caption,
  });

  factory MomentPreview.fromJson(Map<String, dynamic> json) => MomentPreview(
    id: json['id'].toString(),
    kind: json['kind'] == 'video' ? MomentKind.video : MomentKind.photo,
    caption: json['caption'] as String?,
    thumbnail: base64Decode(json['thumbnail'] as String),
  );

  factory MomentPreview.of(Moment moment) => MomentPreview(
    id: moment.id,
    kind: moment.kind,
    caption: moment.caption,
    thumbnail: moment.thumbnail,
  );

  final String id;
  final MomentKind kind;
  final String? caption;
  final Uint8List thumbnail;
}
