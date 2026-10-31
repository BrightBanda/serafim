/// What a collection item is. Stored by name, so new kinds can go anywhere.
enum StickerCollectionItemKind { sticker, gif, video, audio }

/// One item saved inside a [StickerCollection].
///
/// A sticker is saved by id (e.g. 'doodles/frog'): the art ships with the
/// app. A GIF, video or audio file is saved as a file on this device (see
/// `SavedMediaStore`); the item keeps only that file's name, which is
/// derived from its contents, so the same file saved twice is one item.
class StickerCollectionItem {
  const StickerCollectionItem.sticker(this.stickerId, {this.name})
    : kind = StickerCollectionItemKind.sticker,
      file = null,
      legacyBytesBase64 = null;

  const StickerCollectionItem.media({
    required this.kind,
    required String this.file,
    this.name,
  }) : assert(kind != StickerCollectionItemKind.sticker),
       stickerId = null,
       legacyBytesBase64 = null;

  const StickerCollectionItem._legacyGif({
    required String this.legacyBytesBase64,
    this.name,
  }) : kind = StickerCollectionItemKind.gif,
       stickerId = null,
       file = null;

  final StickerCollectionItemKind kind;

  /// Stickers: `pack/name`.
  final String? stickerId;

  /// GIFs, videos and audio: the saved file's name (`<sha1>.<ext>`).
  final String? file;

  /// What to call it: the sticker's or the file's name.
  final String? name;

  /// A GIF saved by an older version, which kept the bytes inline. Moved to
  /// a file (and this cleared) the first time the collections load.
  final String? legacyBytesBase64;

  bool get isSticker => kind == StickerCollectionItemKind.sticker;
  bool get isGif => kind == StickerCollectionItemKind.gif;
  bool get isVideo => kind == StickerCollectionItemKind.video;
  bool get isAudio => kind == StickerCollectionItemKind.audio;
  bool get needsMigration => legacyBytesBase64 != null;

  /// Identifies the item across collections: one sticker, or one file's
  /// contents.
  String get key => isSticker
      ? 'sticker:$stickerId'
      : file != null
      ? 'file:$file'
      : 'legacy:${legacyBytesBase64.hashCode}';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (stickerId != null) 'sticker_id': stickerId,
    if (file != null) 'file': file,
    if (name != null) 'name': name,
    // Only until migrated; never written for new items.
    if (legacyBytesBase64 != null) 'gif_bytes': legacyBytesBase64,
  };

  /// Null for an entry this version cannot use.
  static StickerCollectionItem? fromJson(Map<String, dynamic> json) {
    final kind = StickerCollectionItemKind.values.asNameMap()[json['kind']];
    final name = json['name'] as String?;
    if (kind == null) return null;
    if (kind == StickerCollectionItemKind.sticker) {
      final id = json['sticker_id'] as String?;
      return id == null || id.isEmpty
          ? null
          : StickerCollectionItem.sticker(id, name: name);
    }
    final file = json['file'] as String?;
    if (file != null && file.isNotEmpty) {
      return StickerCollectionItem.media(kind: kind, file: file, name: name);
    }
    final legacy = json['gif_bytes'] as String?;
    if (kind == StickerCollectionItemKind.gif &&
        legacy != null &&
        legacy.isNotEmpty) {
      return StickerCollectionItem._legacyGif(
        legacyBytesBase64: legacy,
        name: name,
      );
    }
    return null;
  }
}

/// A named collection of saved stickers, GIFs, videos and audio, kept on
/// the device for one account.
class StickerCollection {
  const StickerCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    this.items = const [],
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// The saved items in this collection, newest first.
  final List<StickerCollectionItem> items;

  bool get isEmpty => items.isEmpty;

  StickerCollection copyWith({
    String? name,
    List<StickerCollectionItem>? items,
  }) => StickerCollection(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    items: items ?? this.items,
  );

  bool contains(String itemKey) => items.any((i) => i.key == itemKey);

  /// The sticker ids in this collection.
  List<String> get stickerIds => [
    for (final i in items)
      if (i.isSticker) i.stickerId!,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'items': [for (final i in items) i.toJson()],
  };

  factory StickerCollection.fromJson(Map<String, dynamic> json) =>
      StickerCollection(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        items: [
          for (final e in (json['items'] as List? ?? const []))
            if (e is Map<String, dynamic>) ?StickerCollectionItem.fromJson(e),
        ],
      );
}
