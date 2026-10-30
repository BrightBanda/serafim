import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/sticker_collection.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';

/// Stickers this account sent recently, newest first (kept on the device).
class RecentStickersNotifier extends Notifier<List<String>> {
  static const max = 16;

  @override
  List<String> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    // Drop ids this version of the app no longer has.
    return ref
        .read(localCacheProvider)
        .recentStickers(account)
        .where((id) => stickerById(id) != null)
        .toList();
  }

  void used(String id) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    state = [id, ...state.where((s) => s != id)].take(max).toList();
    ref.read(localCacheProvider).saveRecentStickers(account, state);
  }
}

final recentStickersProvider =
    NotifierProvider<RecentStickersNotifier, List<String>>(
      RecentStickersNotifier.new,
    );

/// This account's saved sticker collections (kept on the device).
class StickerCollectionsNotifier extends Notifier<List<StickerCollection>> {
  @override
  List<StickerCollection> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    return ref.read(localCacheProvider).stickerCollections(account);
  }

  StickerCollection createCollection(String name) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) throw StateError('No signed-in account');

    final collection = StickerCollection(
      id: 'coll_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now().toUtc(),
    );
    state = [...state, collection];
    ref.read(localCacheProvider).saveStickerCollections(account, state);
    return collection;
  }

  /// Adds [item] to [collectionId], creating the collection if needed.
  /// Returns the (possibly new) collection. [collectionName] is only used when
  /// creating a new collection.
  StickerCollection addToCollection({
    required String collectionId,
    String? collectionName,
    required StickerCollectionItem item,
  }) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) throw StateError('No signed-in account');

    final collections = [...state];
    final existing = collections.indexWhere((c) => c.id == collectionId);

    if (existing >= 0) {
      final collection = collections[existing];
      if (item.isSticker && collection.containsSticker(item.stickerId)) {
        return collection; // already in this collection
      }
      if (item.isGif &&
          collection.containsGifName(item.name ?? item.stickerId)) {
        return collection; // already in this collection
      }
      final updated = collection.copyWith(items: [item, ...collection.items]);
      collections[existing] = updated;
      state = collections;
      ref.read(localCacheProvider).saveStickerCollections(account, collections);
      return updated;
    }

    // Create a new collection.
    final now = DateTime.now().toUtc();
    final newCollection = StickerCollection(
      id: collectionId,
      name: collectionName ?? 'New collection',
      createdAt: now,
      items: [item],
    );
    collections.add(newCollection);
    state = collections;
    ref.read(localCacheProvider).saveStickerCollections(account, collections);
    return newCollection;
  }

  /// Removes [stickerId] (a sticker item) from [collectionId].
  void removeStickerFromCollection({
    required String collectionId,
    required String stickerId,
  }) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    final collections = [
      for (final c in state)
        if (c.id == collectionId)
          c.copyWith(
            items: [
              for (final i in c.items)
                if (!(i.isSticker && i.stickerId == stickerId)) i,
            ],
          )
        else
          c,
    ];
    state = collections;
    ref.read(localCacheProvider).saveStickerCollections(account, collections);
  }

  /// Removes a GIF item named [gifName] from [collectionId].
  void removeGifFromCollection({
    required String collectionId,
    required String gifName,
  }) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    final collections = [
      for (final c in state)
        if (c.id == collectionId)
          c.copyWith(
            items: [
              for (final i in c.items)
                if (!(i.isGif && i.name == gifName)) i,
            ],
          )
        else
          c,
    ];
    state = collections;
    ref.read(localCacheProvider).saveStickerCollections(account, collections);
  }
}

final stickerCollectionsProvider =
    NotifierProvider<StickerCollectionsNotifier, List<StickerCollection>>(
      StickerCollectionsNotifier.new,
    );
