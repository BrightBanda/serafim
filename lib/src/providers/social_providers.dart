import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/social_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
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
final followingProvider = FutureProvider<List<PublicUser>>((ref) {
  if (ref.watch(currentAccountIdProvider) == null) return const [];
  return ref.watch(socialServiceProvider).following();
});

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
      if (account != null)
        await ref.read(localCacheProvider).savePerson(account, user);
      return user;
    });

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
final conversationPeerIdsProvider = StreamProvider<List<String>>((ref) {
  final myId = ref.watch(currentAccountIdProvider);
  if (myId == null) return const Stream.empty();
  return ref.watch(isarServiceProvider).watchConversationPeerIds(myId);
});

/// Friend-request commands. Each returns null on success or a message to
/// show, and refreshes every list the change could affect.
class SocialActions {
  SocialActions(this._ref);

  final Ref _ref;

  SocialService get _service => _ref.read(socialServiceProvider);

  Future<String?> sendRequest(String userId) =>
      _run(() => _service.sendRequest(userId));
  Future<String?> accept(String userId) => _run(() => _service.accept(userId));
  Future<String?> reject(String userId) => _run(() => _service.reject(userId));
  Future<String?> cancel(String userId) => _run(() => _service.cancel(userId));
  Future<String?> unfriend(String userId) =>
      _run(() => _service.unfriend(userId));

  Future<String?> follow(String userId) => _run(() async {
    await _service.follow(userId);
    return FriendStatus.none;
  });

  Future<String?> unfollow(String userId) => _run(() async {
    await _service.unfollow(userId);
    return FriendStatus.none;
  });

  Future<String?> _run(Future<FriendStatus> Function() action) async {
    try {
      await action();
      refreshAll(_ref);
      return null;
    } on ApiException catch (error) {
      // The other side may have changed things first; resync either way.
      refreshAll(_ref);
      return error.message;
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
  }
}

final socialActionsProvider = Provider<SocialActions>(SocialActions.new);
