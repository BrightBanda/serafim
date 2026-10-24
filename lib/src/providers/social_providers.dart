import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/social_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/relation_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

final socialServiceProvider = Provider<SocialService>((ref) {
  return SocialService(ref.watch(apiDioProvider));
});

// Everything below is keyed on the account id so a different person signing
// in never sees the previous account's friends.

/// People you are friends with, fetched from the server. A copy is saved on
/// the phone each time, so the next launch can show it before this finishes —
/// screens should read [friendsViewProvider], which does that.
final friendsProvider = FutureProvider<List<PublicUser>>((ref) async {
  final account = ref.watch(currentAccountIdProvider);
  if (account == null) return const [];
  final friends = await ref.watch(socialServiceProvider).friends();

  final cache = ref.read(localCacheProvider);
  await cache.saveFriends(account, friends);
  for (final f in friends) {
    await cache.savePerson(account, f); // So their profile opens instantly too.
  }
  return friends;
});

/// What to show for the friends list *right now*: the server's answer once it
/// has arrived, otherwise the copy saved on this phone. This is why the chat
/// list appears instantly on launch instead of after a spinner.
class FriendsView {
  const FriendsView({
    required this.friends,
    required this.hasData,
    required this.isRefreshing,
    this.error,
  });

  final List<PublicUser> friends;

  /// There is something to show (fresh or saved), even if it may be a moment old.
  final bool hasData;

  /// A request is in flight (the list on screen may be the saved copy).
  final bool isRefreshing;

  /// Why loading failed, only when there is nothing at all to show.
  final Object? error;
}

final friendsViewProvider = Provider<FriendsView>((ref) {
  final account = ref.watch(currentAccountIdProvider);
  final fresh = ref.watch(friendsProvider);
  final saved = account == null
      ? null
      : ref.read(localCacheProvider).friends(account);

  final friends = fresh.value ?? saved;
  return FriendsView(
    friends: friends ?? const [],
    hasData: friends != null,
    isRefreshing: fresh.isLoading,
    error: friends == null && fresh.hasError ? fresh.error : null,
  );
});

/// Pending requests, both directions.
final friendRequestsProvider = FutureProvider<FriendRequests>((ref) {
  if (ref.watch(currentAccountIdProvider) == null) {
    return const FriendRequests();
  }
  return ref.watch(socialServiceProvider).requests();
});

/// People you follow / people who follow you.
///
/// The ids of the people you follow are saved on the phone each time, so the
/// next launch labels Follow buttons correctly before this finishes.
final followingProvider = FutureProvider<List<PublicUser>>((ref) async {
  final account = ref.watch(currentAccountIdProvider);
  if (account == null) return const [];
  final following = await ref.watch(socialServiceProvider).following();
  await ref.read(localCacheProvider).saveFollowingIds(account, [
    for (final u in following) u.id,
  ]);
  return following;
});

/// Ids of everyone you follow: the server's list once it has arrived (kept
/// while it refreshes), otherwise the copy saved on this phone, otherwise null
/// — not known yet.
///
/// This, not the `isFollowing` inside a post's author, is the truth for Follow
/// buttons: a post is a snapshot from when the feed loaded, and is not
/// refetched when you follow or unfollow its author.
final followingIdsProvider = Provider<Set<String>?>((ref) {
  final account = ref.watch(currentAccountIdProvider);
  if (account == null) return null;
  final fresh = ref.watch(followingProvider).value;
  if (fresh != null) return {for (final u in fresh) u.id};
  return ref.read(localCacheProvider).followingIds(account);
});

/// Whether you follow [user], as best known right now: a tap still on its way,
/// else your following list (fresh or saved), else what [user] itself says.
/// Null while the list is still loading for the first time ever, so a button
/// never shows "Follow" for someone you already follow.
bool? watchIsFollowing(WidgetRef ref, PublicUser user) {
  final pending = ref.watch(
    relationOverridesProvider.select((o) => o.follow[user.id]),
  );
  if (pending != null) return pending;
  final known = ref.watch(
    followingIdsProvider.select((ids) => ids?.contains(user.id)),
  );
  if (known != null) return known;
  if (ref.watch(followingProvider.select((a) => a.isLoading))) return null;
  return user.isFollowing; // The list failed and nothing is saved.
}

final followersProvider = FutureProvider<List<PublicUser>>((ref) {
  if (ref.watch(currentAccountIdProvider) == null) return const [];
  return ref.watch(socialServiceProvider).followers();
});

/// Suggested people (not friends), best matches first.
final discoverProvider = FutureProvider<List<PublicUser>>((ref) {
  if (ref.watch(currentAccountIdProvider) == null) return const [];
  return ref.watch(socialServiceProvider).discover();
});

/// Search results for an already-debounced, trimmed query.
final userSearchProvider = FutureProvider.autoDispose
    .family<List<PublicUser>, String>((ref, query) {
      return ref.watch(socialServiceProvider).search(query);
    });

/// One person's public profile, including their relationship to you, from the
/// server (and saved on the phone for next time).
final publicUserProvider = FutureProvider.autoDispose
    .family<PublicUser, String>((ref, id) async {
      final user = await ref.watch(socialServiceProvider).user(id);
      final account = ref.read(currentAccountIdProvider);
      if (account != null) {
        await ref.read(localCacheProvider).savePerson(account, user);
      }
      return user;
    });

/// Someone else's friends, followers and following. These fail with a
/// "profile is locked" error when that person has locked their profile.
final friendsOfProvider = FutureProvider.autoDispose
    .family<List<PublicUser>, String>(
      (ref, id) => ref.watch(socialServiceProvider).friendsOf(id),
    );

final followersOfProvider = FutureProvider.autoDispose
    .family<List<PublicUser>, String>(
      (ref, id) => ref.watch(socialServiceProvider).followersOf(id),
    );

final followingOfProvider = FutureProvider.autoDispose
    .family<List<PublicUser>, String>(
      (ref, id) => ref.watch(socialServiceProvider).followingOf(id),
    );

/// Someone you know about, instantly and without the network: a friend, else
/// the copy saved on this phone, else null. Screens show this immediately and
/// let [publicUserProvider] bring in anything fresher.
final knownPersonProvider = Provider.family<PublicUser?, String>((ref, id) {
  final account = ref.watch(currentAccountIdProvider);
  if (account == null) return null;
  final friends = ref.watch(friendsViewProvider).friends;
  for (final f in friends) {
    if (f.id == id) return f;
  }
  return ref.read(localCacheProvider).person(account, id);
});

/// Ids of confirmed friends. Empty until a friends list (fresh or saved) exists.
final friendIdsProvider = Provider<Set<String>>((ref) {
  final friends = ref.watch(friendsViewProvider).friends;
  return {for (final f in friends) f.id};
});

/// Everyone you have exchanged messages with, friend or not.
///
/// Read from the phone synchronously on the first build (see
/// [ChatRoomsNotifier] for why), then kept up to date.
class ConversationPeersNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final myId = ref.watch(currentAccountIdProvider);
    if (myId == null) return const [];
    final service = ref.watch(isarServiceProvider);
    final changes = service
        .watchConversationPeerIds(myId, fireImmediately: false)
        .listen((ids) => state = ids);
    ref.onDispose(changes.cancel);
    return service.peerIdsNow(myId);
  }
}

final conversationPeerIdsProvider =
    NotifierProvider<ConversationPeersNotifier, List<String>>(
      ConversationPeersNotifier.new,
    );

/// Friend and follow commands, applied optimistically: the screen shows the
/// result of a tap straight away (through [relationOverridesProvider]) while
/// the request runs in the background. Each command returns null on success
/// or a message to show; on failure the change is rolled back.
///
/// Rapid taps never produce duplicate or out-of-order requests: friend
/// commands for someone are ignored while one is already in flight, and
/// follow/unfollow taps are coalesced so only the latest wish is sent once the
/// current request finishes.
class SocialActions {
  SocialActions(this._ref);

  final Ref _ref;

  SocialService get _service => _ref.read(socialServiceProvider);
  RelationOverridesNotifier get _overrides =>
      _ref.read(relationOverridesProvider.notifier);

  /// People with a friend command on its way to the server.
  final Set<String> _friendBusy = {};

  /// The follow state the user last asked for, per person, while a follow
  /// request for them is running.
  final Map<String, bool> _wantFollow = {};

  Future<String?> sendRequest(String userId) => _friend(
    userId,
    FriendStatus.requestSent,
    () => _service.sendRequest(userId),
  );
  Future<String?> accept(String userId) =>
      _friend(userId, FriendStatus.friends, () => _service.accept(userId));
  Future<String?> reject(String userId) =>
      _friend(userId, FriendStatus.none, () => _service.reject(userId));
  Future<String?> cancel(String userId) =>
      _friend(userId, FriendStatus.none, () => _service.cancel(userId));
  Future<String?> unfriend(String userId) =>
      _friend(userId, FriendStatus.none, () => _service.unfriend(userId));

  Future<String?> follow(String userId) => setFollowing(userId, true);
  Future<String?> unfollow(String userId) => setFollowing(userId, false);

  Future<String?> _friend(
    String userId,
    FriendStatus optimistic,
    Future<FriendStatus> Function() action,
  ) async {
    if (!_friendBusy.add(userId)) return null; // Already on its way.
    _overrides.setFriend(userId, optimistic);
    try {
      // The server's answer can differ from the guess (asking someone who
      // already asked you makes you friends), so show what it said.
      _overrides.setFriend(userId, await action());
      await _resync(userId);
      _overrides.clearFriend(userId);
      return null;
    } on ApiException catch (error) {
      _overrides.clearFriend(userId);
      // The other side may have changed things first; resync either way.
      refreshAll(_ref);
      return error.message;
    } finally {
      _friendBusy.remove(userId);
    }
  }

  /// Follows or unfollows [userId], showing the new state at once.
  Future<String?> setFollowing(String userId, bool following) async {
    _overrides.setFollow(userId, following);
    final running = _wantFollow.containsKey(userId);
    _wantFollow[userId] = following;
    if (running) return null; // The running loop below sends the latest wish.

    bool? sent;
    try {
      while (true) {
        final want = _wantFollow[userId]!;
        if (want != sent) {
          want
              ? await _service.follow(userId)
              : await _service.unfollow(userId);
          sent = want;
          continue;
        }
        await _resync(userId);
        // A tap may have landed while the lists were refreshing.
        if (_wantFollow[userId] == sent) break;
      }
      _overrides.clearFollow(userId);
      return null;
    } on ApiException catch (error) {
      _overrides.clearFollow(userId);
      refreshAll(_ref);
      return error.message;
    } finally {
      _wantFollow.remove(userId);
    }
  }

  /// Refetches every list the change could affect and waits (briefly) for
  /// the ones on screen, so dropping the pending change never flashes the old
  /// state back.
  Future<void> _resync(String userId) async {
    refreshAll(_ref);
    final waits = <Future<Object?>>[
      if (_ref.exists(friendsProvider)) _ref.read(friendsProvider.future),
      if (_ref.exists(friendRequestsProvider))
        _ref.read(friendRequestsProvider.future),
      if (_ref.exists(followingProvider)) _ref.read(followingProvider.future),
      if (_ref.exists(followersProvider)) _ref.read(followersProvider.future),
      if (_ref.exists(discoverProvider)) _ref.read(discoverProvider.future),
      if (_ref.exists(publicUserProvider(userId)))
        _ref.read(publicUserProvider(userId).future),
    ];
    try {
      await Future.wait(waits).timeout(const Duration(seconds: 10));
    } catch (_) {
      // A list that failed to refresh shows its own error.
    }
  }

  /// Also called when the server pushes `friend_update`.
  static void refreshAll(Ref ref) {
    ref.invalidate(friendsProvider);
    ref.invalidate(friendRequestsProvider);
    ref.invalidate(followingProvider);
    ref.invalidate(followersProvider);
    ref.invalidate(discoverProvider);
    ref.invalidate(userSearchProvider);
    ref.invalidate(publicUserProvider);
    ref.invalidate(friendsOfProvider);
    ref.invalidate(followersOfProvider);
    ref.invalidate(followingOfProvider);
  }
}

final socialActionsProvider = Provider<SocialActions>(SocialActions.new);
