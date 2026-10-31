import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/local/saved_media_store.dart';
import 'package:serafim/src/data/models/sticker_collection.dart';
import 'package:serafim/src/data/services/chat_media_store.dart'
    show imageExtension;
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';

/// Stickers and GIFs this account sent recently, newest first (kept on the
/// device). A GIF here points at a file in [SavedMediaStore], which stays
/// while either this list or a collection holds it.
class RecentStickersNotifier extends Notifier<List<StickerCollectionItem>> {
  static const max = 16;

  @override
  List<StickerCollectionItem> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    // Drop stickers this version of the app no longer has.
    return [
      for (final item in ref.read(localCacheProvider).recentItems(account))
        if (item.isGif ||
            (item.isSticker && stickerById(item.stickerId!) != null))
          item,
    ];
  }

  /// [item] was just sent. Only stickers and GIFs are kept.
  void used(StickerCollectionItem item) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null || !(item.isSticker || item.isGif)) return;
    final all = [item, ...state.where((s) => s.key != item.key)];
    state = all.take(max).toList();
    ref.read(localCacheProvider).saveRecentItems(account, state);
    for (final gone in all.skip(max)) {
      ref.read(stickerCollectionsProvider.notifier).releaseFile(gone);
    }
  }

  void usedSticker(String stickerId) =>
      used(StickerCollectionItem.sticker(stickerId));

  bool holds(String itemKey) => state.any((i) => i.key == itemKey);
}

final recentStickersProvider =
    NotifierProvider<RecentStickersNotifier, List<StickerCollectionItem>>(
      RecentStickersNotifier.new,
    );

final savedMediaStoreProvider = Provider<SavedMediaStore>(
  (ref) => SavedMediaStore(),
);

/// The folder holding this account's saved collection files, for showing
/// them without waiting on each one.
final savedMediaDirProvider = FutureProvider<String?>((ref) async {
  final account = ref.watch(currentAccountIdProvider);
  if (account == null) return null;
  return (await ref.watch(savedMediaStoreProvider).dirFor(account)).path;
});

/// Something about to be saved to a collection: the item, plus the file to
/// copy in (GIFs, videos, audio) once a collection has been chosen, so
/// backing out of the sheet copies nothing.
class PendingCollectionItem {
  const PendingCollectionItem(this.item, {this.sourcePath});

  PendingCollectionItem.sticker(String stickerId, {String? name})
    : this(StickerCollectionItem.sticker(stickerId, name: name));

  final StickerCollectionItem item;
  final String? sourcePath;
}

/// This account's saved collections of stickers, GIFs, videos and audio.
///
/// The list lives in [LocalCache]; GIF, video and audio files live in
/// [SavedMediaStore], named by their contents, and are deleted once no
/// collection holds them.
class StickerCollectionsNotifier extends Notifier<List<StickerCollection>> {
  @override
  List<StickerCollection> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    final collections = ref
        .read(localCacheProvider)
        .stickerCollections(account);
    if (collections.any((c) => c.items.any((i) => i.needsMigration))) {
      Future.microtask(() => _migrateLegacy(account));
    }
    return collections;
  }

  SavedMediaStore get _store => ref.read(savedMediaStoreProvider);

  String _requireAccount() {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) throw StateError('No signed-in account');
    return account;
  }

  void _commit(String account, List<StickerCollection> collections) {
    // The account may have changed during an await: never write one
    // account's collections under another.
    if (ref.read(currentAccountIdProvider) != account) return;
    state = collections;
    ref.read(localCacheProvider).saveStickerCollections(account, collections);
  }

  StickerCollection createCollection(String name) {
    final account = _requireAccount();
    final collection = StickerCollection(
      id: 'coll_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now().toUtc(),
    );
    _commit(account, [...state, collection]);
    return collection;
  }

  /// Whether a collection named [name] exists (ignoring case).
  bool nameTaken(String name) {
    final lower = name.trim().toLowerCase();
    return state.any((c) => c.name.toLowerCase() == lower);
  }

  /// Gets the GIF, video or audio file at [path] ready to save. Reads the
  /// file through once to name it by its contents; copies nothing yet.
  Future<PendingCollectionItem> prepareFile(
    String path,
    StickerCollectionItemKind kind, {
    String? name,
  }) async {
    final file = await _store.nameFor(path);
    return PendingCollectionItem(
      StickerCollectionItem.media(kind: kind, file: file, name: name),
      sourcePath: path,
    );
  }

  /// Saves [pending] at the front of [collectionId]. Returns false when it
  /// was already there.
  Future<bool> add(String collectionId, PendingCollectionItem pending) async {
    final account = _requireAccount();
    final item = pending.item;
    final target = state.where((c) => c.id == collectionId).firstOrNull;
    if (target == null) return false;
    if (target.contains(item.key)) return false;
    await _copyIn(account, pending);
    _commit(account, [
      for (final c in state)
        if (c.id == collectionId && !c.contains(item.key))
          c.copyWith(items: [item, ...c.items])
        else
          c,
    ]);
    return true;
  }

  /// Creates a collection called [name] holding [pending].
  Future<StickerCollection> addToNew(
    String name,
    PendingCollectionItem pending,
  ) async {
    final account = _requireAccount();
    await _copyIn(account, pending);
    final collection = StickerCollection(
      id: 'coll_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now().toUtc(),
      items: [pending.item],
    );
    _commit(account, [...state, collection]);
    return collection;
  }

  Future<void> _copyIn(String account, PendingCollectionItem pending) async {
    final file = pending.item.file;
    final source = pending.sourcePath;
    if (file != null && source != null) {
      await _store.adopt(account, source, file);
    }
  }

  /// Removes the item with [itemKey] from [collectionId], or from every
  /// collection when none is given. Its file goes once nothing holds it.
  /// Returns how many collections it was removed from.
  Future<int> remove(String itemKey, {String? collectionId}) async {
    final account = _requireAccount();
    bool affected(StickerCollection c) =>
        (collectionId == null || c.id == collectionId) && c.contains(itemKey);
    final holders = state.where(affected).toList();
    if (holders.isEmpty) return 0;
    final file = holders.first.items.firstWhere((i) => i.key == itemKey).file;
    final collections = [
      for (final c in state)
        if (affected(c))
          c.copyWith(items: [...c.items.where((i) => i.key != itemKey)])
        else
          c,
    ];
    _commit(account, collections);
    if (file != null &&
        !collections.any((c) => c.contains(itemKey)) &&
        !ref.read(recentStickersProvider.notifier).holds(itemKey)) {
      await _store.delete(account, file);
    }
    return holders.length;
  }

  /// Deletes [item]'s file once nothing holds it: called when it leaves the
  /// recents.
  Future<void> releaseFile(StickerCollectionItem item) async {
    final account = ref.read(currentAccountIdProvider);
    final file = item.file;
    if (account == null || file == null) return;
    if (state.any((c) => c.contains(item.key))) return;
    if (ref.read(recentStickersProvider.notifier).holds(item.key)) return;
    await _store.delete(account, file);
  }

  /// Where [item]'s file is on this device (GIFs, videos, audio).
  Future<String?> pathOf(StickerCollectionItem item) async {
    final account = ref.read(currentAccountIdProvider);
    final file = item.file;
    if (account == null || file == null) return null;
    return _store.pathOf(account, file);
  }

  /// Older versions kept saved GIFs as base64 inside the collection list;
  /// each is written out to a file once, and the list saved without it.
  Future<void> _migrateLegacy(String account) async {
    final replaced = <String, StickerCollectionItem>{};
    for (final c in state) {
      for (final item in c.items) {
        final legacy = item.legacyBytesBase64;
        if (legacy == null || replaced.containsKey(item.key)) continue;
        try {
          final bytes = base64Decode(legacy);
          final ext = imageExtension(bytes).split('.').last;
          final file = await _store.adoptBytes(account, bytes, extension: ext);
          replaced[item.key] = StickerCollectionItem.media(
            kind: StickerCollectionItemKind.gif,
            file: file,
            name: item.name,
          );
        } on FormatException {
          // Unreadable: dropped below rather than kept forever.
        }
      }
    }
    _commit(account, [
      for (final c in state)
        c.copyWith(
          items: [
            for (final i in c.items)
              if (!i.needsMigration)
                i
              else if (replaced[i.key] case final fixed?)
                fixed,
          ],
        ),
    ]);
  }
}

final stickerCollectionsProvider =
    NotifierProvider<StickerCollectionsNotifier, List<StickerCollection>>(
      StickerCollectionsNotifier.new,
    );
