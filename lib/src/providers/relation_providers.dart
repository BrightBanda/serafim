import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/auth_providers.dart';

/// Relationship changes the user has just made but the server has not yet
/// confirmed (or whose confirmation has not reached every list yet), keyed by
/// the other person's id. Screens lay these over whatever the server last
/// said, so a tap shows its result at once.
class RelationOverrides {
  const RelationOverrides({this.friend = const {}, this.follow = const {}});

  final Map<String, FriendStatus> friend;
  final Map<String, bool> follow;
}

extension PublicUserRelation on PublicUser {
  /// This person with an unconfirmed change laid over them. Applying the same
  /// change twice is harmless: the follower count only moves when the follow
  /// state actually differs from what the server said.
  PublicUser withRelation({FriendStatus? friendStatus, bool? isFollowing}) {
    if (friendStatus == null && isFollowing == null) return this;
    final following = isFollowing ?? this.isFollowing;
    final count = followerCount;
    return copyWith(
      friendStatus: friendStatus,
      isFollowing: following,
      followerCount: count == null || following == this.isFollowing
          ? count
          : (following ? count + 1 : (count > 0 ? count - 1 : 0)),
    );
  }
}

class RelationOverridesNotifier extends Notifier<RelationOverrides> {
  @override
  RelationOverrides build() {
    // A different account never inherits someone else's pending taps.
    ref.watch(currentAccountIdProvider);
    return const RelationOverrides();
  }

  void setFriend(String userId, FriendStatus status) =>
      state = RelationOverrides(
        friend: {...state.friend, userId: status},
        follow: state.follow,
      );

  void clearFriend(String userId) => state = RelationOverrides(
    friend: {...state.friend}..remove(userId),
    follow: state.follow,
  );

  void setFollow(String userId, bool following) => state = RelationOverrides(
    friend: state.friend,
    follow: {...state.follow, userId: following},
  );

  void clearFollow(String userId) => state = RelationOverrides(
    friend: state.friend,
    follow: {...state.follow}..remove(userId),
  );
}

final relationOverridesProvider =
    NotifierProvider<RelationOverridesNotifier, RelationOverrides>(
      RelationOverridesNotifier.new,
    );

/// [user] with any pending change applied. Rebuilds only when that person's
/// own pending state changes.
PublicUser watchWithPending(WidgetRef ref, PublicUser user) {
  final friend = ref.watch(
    relationOverridesProvider.select((o) => o.friend[user.id]),
  );
  final follow = ref.watch(
    relationOverridesProvider.select((o) => o.follow[user.id]),
  );
  return user.withRelation(friendStatus: friend, isFollowing: follow);
}
