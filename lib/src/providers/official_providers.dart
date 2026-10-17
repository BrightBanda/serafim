import 'package:flutter_riverpod/flutter_riverpod.dart';
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
