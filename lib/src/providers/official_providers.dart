import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/data/services/official_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

final officialServiceProvider = Provider<OfficialService>((ref) {
  return OfficialService(ref.watch(apiDioProvider));
});

/// What the official SERAFIM chat shows.
class OfficialChatState {
  const OfficialChatState({
    this.announcements = const [],
    this.canPost = false,
    this.hasMore = false,
    this.isRefreshing = false,
  });

  /// Newest first.
  final List<Announcement> announcements;

  /// This user is an administrator (the server decides; it re-checks on post).
  final bool canPost;

  /// Older announcements exist beyond the ones loaded.
  final bool hasMore;

  /// Showing the copy saved on the phone while the server is asked.
  final bool isRefreshing;

  Announcement? get latest =>
      announcements.isEmpty ? null : announcements.first;

  OfficialChatState copyWith({
    List<Announcement>? announcements,
    bool? canPost,
    bool? hasMore,
    bool? isRefreshing,
  }) => OfficialChatState(
    announcements: announcements ?? this.announcements,
    canPost: canPost ?? this.canPost,
    hasMore: hasMore ?? this.hasMore,
    isRefreshing: isRefreshing ?? this.isRefreshing,
  );
}

/// The official chat, which every account has without adding anyone. Like the
/// friends list it opens from the copy saved on the phone and refreshes from
/// the server behind it; live announcements arrive over the socket.
class OfficialChatController extends AsyncNotifier<OfficialChatState> {
  static const pageSize = 50;

  OfficialService get _service => ref.read(officialServiceProvider);

  @override
  Future<OfficialChatState> build() async {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const OfficialChatState();

    final saved = ref.read(localCacheProvider).announcements(account);
    if (saved != null) {
      Future.microtask(() => _revalidate(account));
      return OfficialChatState(announcements: saved, isRefreshing: true);
    }
    return _fetch(account);
  }

  Future<OfficialChatState> _fetch(String account) async {
    final results = await Future.wait([
      _service.info(),
      _service.announcements(limit: pageSize),
    ]);
    final info = results[0] as OfficialChatInfo;
    final items = results[1] as List<Announcement>;
    await ref.read(localCacheProvider).saveAnnouncements(account, items);
    return OfficialChatState(
      announcements: items,
      canPost: info.canPost,
      hasMore: items.length >= pageSize,
    );
  }

  Future<void> _revalidate(String account) async {
    try {
      final fresh = await _fetch(account);
      if (!ref.mounted || ref.read(currentAccountIdProvider) != account) return;
      state = AsyncData(fresh);
    } catch (_) {
      // Offline: keep the saved copy on screen.
      final current = state.value;
      if (ref.mounted && current != null) {
        state = AsyncData(current.copyWith(isRefreshing: false));
      }
    }
  }

  /// Pull to refresh / retry.
  Future<void> reload() async {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(current.copyWith(isRefreshing: true));
    await _revalidate(account);
  }

  bool _loadingOlder = false;

  /// Fetches the page before the oldest announcement shown.
  Future<void> loadOlder() async {
    final current = state.value;
    if (_loadingOlder || current == null || !current.hasMore) return;
    final oldest = current.announcements.lastOrNull;
    if (oldest == null) return;
    _loadingOlder = true;
    try {
      final older = await _service.announcements(
        before: oldest.createdAt,
        limit: pageSize,
      );
      final now = state.value ?? current;
      state = AsyncData(
        now.copyWith(
          announcements: _merge(now.announcements, older),
          hasMore: older.length >= pageSize,
        ),
      );
    } catch (_) {
      // Scrolling up again retries.
    } finally {
      _loadingOlder = false;
    }
  }

  /// Administrators only. Returns null on success or a message to show.
  Future<String?> post(String content) async {
    final text = content.trim();
    if (text.isEmpty) return 'An announcement cannot be empty.';
    try {
      final created = await _service.post(text);
      _insert(created);
      return null;
    } catch (error) {
      return humanError(error, fallback: "Couldn't post the announcement.");
    }
  }

  /// Administrators only: uploads [file] and announces it, with [content] as
  /// its words (which may be empty). Returns null on success or a message to
  /// show.
  Future<String?> postVideo(
    PickedChatFile file, {
    String content = '',
    void Function(double progress)? onProgress,
  }) async {
    final contentType =
        chatFileContentType(file.name, ChatFileKind.video) ??
        chatFileContentType(file.path, ChatFileKind.video);
    if (contentType == null) {
      return "That video format can't be sent. Try MP4, MOV or WebM.";
    }
    try {
      final uploadPath = await _service.startVideoUpload(
        contentType: contentType,
        size: file.size,
      );
      Uint8List? thumbnail;
      try {
        thumbnail = await ref.read(videoThumbnailerProvider)(file.path);
      } catch (_) {
        // It still works without a preview picture.
      }
      await ref
          .read(chatFileServiceProvider)
          .upload(
            clientId: uploadPath,
            path: file.path,
            uploadPath: uploadPath,
            contentType: contentType,
            onProgress: onProgress,
          );
      _insert(
        await _service.post(
          content.trim(),
          video: {
            'upload_path': uploadPath,
            'file_name': file.name,
            'duration_ms': file.durationMs ?? 0,
            if (thumbnail != null) 'thumbnail': base64Encode(thumbnail),
          },
        ),
      );
      return null;
    } catch (error) {
      return humanError(error, fallback: "Couldn't post the video.");
    }
  }

  /// Administrators only: announces an Android release. Returns null on
  /// success or a message to show.
  Future<String?> postUpdate(AppUpdate update) async {
    try {
      _insert(await _service.post('', update: update));
      return null;
    } catch (error) {
      return humanError(error, fallback: "Couldn't post the update.");
    }
  }

  /// Administrators only. Returns null on success or a message to show.
  Future<String?> delete(String id) async {
    try {
      await _service.delete(id);
      removeLocal(id);
      return null;
    } catch (error) {
      return humanError(error, fallback: "Couldn't delete the announcement.");
    }
  }

  /// A live announcement from the socket (or our own post's echo).
  void receive(Announcement announcement) => _insert(announcement);

  void removeLocal(String id) {
    // Its video is gone for everyone now, so this phone's copy goes too.
    unawaited(ref.read(officialVideoStoreProvider).forget(id));
    final current = state.value;
    if (current == null) return;
    _save(
      current.copyWith(
        announcements: [
          for (final a in current.announcements)
            if (a.id != id) a,
        ],
      ),
    );
  }

  void _insert(Announcement announcement) {
    final current = state.value ?? const OfficialChatState();
    _save(
      current.copyWith(
        announcements: _merge(current.announcements, [announcement]),
      ),
    );
  }

  void _save(OfficialChatState next) {
    state = AsyncData(next);
    final account = ref.read(currentAccountIdProvider);
    if (account != null) {
      ref
          .read(localCacheProvider)
          .saveAnnouncements(
            account,
            next.announcements.take(pageSize).toList(),
          );
    }
  }

  /// One entry per id, newest first.
  static List<Announcement> _merge(List<Announcement> a, List<Announcement> b) {
    final byId = {for (final x in a) x.id: x, for (final x in b) x.id: x};
    return byId.values.toList()
      ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
  }
}

/// The videos of announcements on this phone. Kept in the app's own files,
/// outside the chat database, so "keep messages for" never removes them; a copy
/// only goes when its announcement is deleted.
class OfficialVideoStore {
  OfficialVideoStore(this._ref);
  final Ref _ref;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/official_videos').create(recursive: true);
  }

  static String _extension(AnnouncementVideo video) {
    final name = video.name;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'mp4' : name.substring(dot + 1).toLowerCase();
  }

  /// The video of [announcement] on this phone, fetching it the first time.
  Future<String> fileFor(
    Announcement announcement, {
    void Function(double progress)? onProgress,
  }) async {
    final video = announcement.video!;
    final path =
        '${(await _dir()).path}/${announcement.id}.${_extension(video)}';
    if (await File(path).exists()) return path;
    final url = await _ref
        .read(officialServiceProvider)
        .videoUrl(announcement.id);
    await _ref
        .read(chatFileServiceProvider)
        .downloadFrom(url, path, onProgress: onProgress);
    return path;
  }

  /// Removes this phone's copy of a deleted announcement's video. Never throws.
  Future<void> forget(String announcementId) async {
    try {
      await for (final f in (await _dir()).list()) {
        if (f.uri.pathSegments.last.startsWith('$announcementId.')) {
          await f.delete();
        }
      }
    } catch (_) {}
  }
}

final officialVideoStoreProvider = Provider<OfficialVideoStore>(
  OfficialVideoStore.new,
);

final officialChatProvider =
    AsyncNotifierProvider<OfficialChatController, OfficialChatState>(
      OfficialChatController.new,
    );

/// When this user last looked at the official chat, kept on the phone.
class OfficialLastReadNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return null;
    return ref.read(localCacheProvider).officialLastRead(account);
  }

  void markSeen(DateTime upTo) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    if (state != null && !upTo.isAfter(state!)) return;
    state = upTo;
    ref.read(localCacheProvider).saveOfficialLastRead(account, upTo);
  }
}

final officialLastReadProvider =
    NotifierProvider<OfficialLastReadNotifier, DateTime?>(
      OfficialLastReadNotifier.new,
    );

/// Whether the official chat has an announcement this user has not seen.
final officialUnreadProvider = Provider<bool>((ref) {
  final latest = ref.watch(officialChatProvider).value?.latest;
  if (latest == null) return false;
  final seen = ref.watch(officialLastReadProvider);
  return seen == null || latest.createdAt.isAfter(seen);
});
