import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

/// Whether a chat removed at [removedAt] stays off the list. It comes back as
/// soon as its latest message ([lastActivity]) is newer than the removal, so
/// a new message is never missed.
bool isChatRemoved(DateTime? removedAt, DateTime? lastActivity) =>
    removedAt != null &&
    (lastActivity == null || !lastActivity.isAfter(removedAt));

/// Chats taken off the chat list ("Remove chat"), by room id, with when.
/// Saved on the phone, per account.
class RemovedChatsNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const {};
    return ref.read(localCacheProvider).removedChats(account);
  }

  void remove(String roomId, DateTime at) => _save({...state, roomId: at});

  void _save(Map<String, DateTime> rooms) {
    state = rooms;
    final account = ref.read(currentAccountIdProvider);
    if (account != null) {
      ref.read(localCacheProvider).saveRemovedChats(account, rooms);
    }
  }
}

final removedChatsProvider =
    NotifierProvider<RemovedChatsNotifier, Map<String, DateTime>>(
      RemovedChatsNotifier.new,
    );

/// What a long press on the chat list can do. Everything stays on this
/// device: the other person (or the group) keeps their copy.
class ChatListActions {
  ChatListActions(this._ref);

  final Ref _ref;

  /// Deletes every message in the chat from this device. The chat stays on
  /// the list.
  Future<void> clear(String roomId) =>
      _ref.read(isarServiceProvider).clearRoomForMe(roomId);

  /// Clears the chat and takes it off the list until a new message arrives.
  ///
  /// Marked with the chat's own latest message time rather than the phone's
  /// clock: messages carry the server's time, and a phone set a few minutes
  /// fast would otherwise keep a brand new message hidden.
  Future<void> remove(String roomId) async {
    final last = _ref.read(roomPreviewsProvider)[roomId]?.timestamp;
    await clear(roomId);
    _ref
        .read(removedChatsProvider.notifier)
        .remove(roomId, last ?? DateTime.fromMillisecondsSinceEpoch(0));
  }
}

final chatListActionsProvider = Provider<ChatListActions>(ChatListActions.new);
