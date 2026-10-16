import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/social_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final socialServiceProvider = Provider<SocialService>((ref) {
  return SocialService(ref.watch(apiDioProvider));
});

// Everything below is keyed on the account id so a different person signing
// in never sees the previous account's friends.

/// People you are friends with.
final friendsProvider = FutureProvider<List<PublicUser>>((ref) {
  if (ref.watch(currentAccountIdProvider) == null) return const [];
  return ref.watch(socialServiceProvider).friends();
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

/// One person's public profile, including their relationship to you.
final publicUserProvider = FutureProvider.autoDispose
    .family<PublicUser, String>((ref, id) {
      return ref.watch(socialServiceProvider).user(id);
    });

/// Ids of confirmed friends. Empty until [friendsProvider] has loaded.
final friendIdsProvider = Provider<Set<String>>((ref) {
  final friends = ref.watch(friendsProvider).value ?? const [];
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
