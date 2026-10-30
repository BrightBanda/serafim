/// A named collection of saved stickers and GIFs, kept on the device for one
/// account.
enum StickerCollectionItemKind { sticker, gif }

/// One item saved inside a [StickerCollection].
///
/// A [sticker] item references a sticker by id (e.g. 'doodles/frog') — the art
/// is drawn by the app, so only the id needs to be stored.
/// A [gif] item stores the GIF's bytes (base64) so it can be resent later.
class StickerCollectionItem {
  const StickerCollectionItem({
    required this.kind,
    required this.stickerId,
    this.name,
    this.gifBytesBase64,
  });

  final StickerCollectionItemKind kind;

  /// For [sticker]: the sticker id (`pack/name`). For [gif]: unused ('').
  final String stickerId;

  /// Display name: sticker name or a name for the saved GIF.
  final String? name;

  /// For [gif]: base64-encoded GIF file bytes. For [sticker]: null.
  final String? gifBytesBase64;

  bool get isGif => kind == StickerCollectionItemKind.gif;
  bool get isSticker => kind == StickerCollectionItemKind.sticker;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'sticker_id': stickerId,
        if (name != null) 'name': name,
        if (gifBytesBase64 != null) 'gif_bytes': gifBytesBase64,
      };

  factory StickerCollectionItem.fromJson(Map<String, dynamic> json) =>
      StickerCollectionItem(
        kind: StickerCollectionItemKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => StickerCollectionItemKind.sticker,
        ),
        stickerId: json['sticker_id'] as String? ?? '',
        name: json['name'] as String?,
        gifBytesBase64: json['gif_bytes'] as String?,
      );
}

/// A named collection of saved stickers and GIFs, kept on the device for one
/// account.
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
  }) =>
      StickerCollection(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        items: items ?? this.items,
      );

  /// Whether this collection already holds [stickerId] as a sticker item.
  bool containsSticker(String stickerId) =>
      items.any((i) => i.isSticker && i.stickerId == stickerId);

  /// Whether this collection already holds a GIF named [name].
  bool containsGifName(String name) =>
      items.any((i) => i.isGif && i.name == name);

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
        createdAt: DateTime.parse(
          json['created_at'] as String? ?? DateTime.now().toUtc().toIso8601String(),
        ).toUtc(),
        items: [
          for (final e in (json['items'] as List? ?? const []))
            StickerCollectionItem.fromJson(e as Map<String, dynamic>),
        ],
      );
}
