import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/data/models/chat_wallpaper.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

/// Gallery photos chosen as chat backgrounds, kept in the app's own folder so
/// they survive the original being deleted from the gallery.
class WallpaperImageStore {
  const WallpaperImageStore();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/chat_wallpapers');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> save(Uint8List jpeg) async {
    final dir = await _dir();
    final file = File(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(jpeg, flush: true);
    return file.path;
  }

  /// Deletes stored photos no chat uses any more.
  Future<void> prune(Set<String> inUse) async {
    try {
      final dir = await _dir();
      await for (final f in dir.list()) {
        if (f is File && !inUse.contains(f.path)) await f.delete();
      }
    } catch (_) {
      // Housekeeping only.
    }
  }
}

final wallpaperImageStoreProvider = Provider<WallpaperImageStore>(
  (ref) => const WallpaperImageStore(),
);

/// Every background choice: the default, and chats that have their own.
class WallpaperSettings {
  const WallpaperSettings({
    this.defaultWallpaper = ChatWallpaper.doodles,
    this.rooms = const {},
  });

  final ChatWallpaper defaultWallpaper;
  final Map<String, ChatWallpaper> rooms;

  ChatWallpaper forRoom(String roomId) => rooms[roomId] ?? defaultWallpaper;

  Set<String> get imagePaths => {
    for (final w in [defaultWallpaper, ...rooms.values])
      if (w.kind == WallpaperKind.image) w.value!,
  };
}

/// Chat backgrounds, saved on this device per account. (They are not synced:
/// a gallery photo only exists on this phone.)
class WallpaperNotifier extends Notifier<WallpaperSettings> {
  @override
  WallpaperSettings build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const WallpaperSettings();
    final cache = ref.read(localCacheProvider);
    return WallpaperSettings(
      defaultWallpaper: ChatWallpaper.decode(cache.defaultWallpaper(account)),
      rooms: cache
          .roomWallpapers(account)
          .map((k, v) => MapEntry(k, ChatWallpaper.decode(v))),
    );
  }

  /// Sets [roomId]'s background, or — with [applyToAll] — every chat's,
  /// replacing any chat-specific choices.
  Future<void> choose(
    String roomId,
    ChatWallpaper wallpaper, {
    required bool applyToAll,
  }) async {
    state = applyToAll
        ? WallpaperSettings(defaultWallpaper: wallpaper)
        : WallpaperSettings(
            defaultWallpaper: state.defaultWallpaper,
            rooms: {...state.rooms, roomId: wallpaper},
          );
    await _persist();
  }

  /// [roomId] goes back to the default background.
  Future<void> resetRoom(String roomId) async {
    state = WallpaperSettings(
      defaultWallpaper: state.defaultWallpaper,
      rooms: {...state.rooms}..remove(roomId),
    );
    await _persist();
  }

  Future<void> _persist() async {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    final cache = ref.read(localCacheProvider);
    final def = state.defaultWallpaper;
    await cache.saveDefaultWallpaper(
      account,
      def == ChatWallpaper.doodles ? null : def.encode(),
    );
    await cache.saveRoomWallpapers(
      account,
      state.rooms.map((k, v) => MapEntry(k, v.encode())),
    );
    await ref.read(wallpaperImageStoreProvider).prune(state.imagePaths);
  }
}

final wallpaperProvider =
    NotifierProvider<WallpaperNotifier, WallpaperSettings>(
      WallpaperNotifier.new,
    );

/// The background to draw for one chat.
final roomWallpaperProvider = Provider.family<ChatWallpaper, String>(
  (ref, roomId) =>
      ref.watch(wallpaperProvider.select((s) => s.forRoom(roomId))),
);

/// Whether [roomId] has its own background (rather than the default).
final roomHasOwnWallpaperProvider = Provider.family<bool, String>(
  (ref, roomId) =>
      ref.watch(wallpaperProvider.select((s) => s.rooms.containsKey(roomId))),
);
