import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';

/// The local database, already open. Overridden in `main`.
final preopenedIsarProvider = Provider<IsarService?>((ref) => null);

/// The one local database. It is told who is signed in, so conversation
/// summaries are about their inbox, and rebuilds those summaries on sign-in.
final isarServiceProvider = Provider<IsarService>((ref) {
  // `main` opens the database before the first frame and hands it in here, so
  // the chat list can read it synchronously. Anything else (tests) opens its
  // own lazily.
  final service = ref.watch(preopenedIsarProvider) ?? IsarService();
  ref.listen<String?>(currentAccountIdProvider, (_, id) {
    service.accountId = id;
    if (id != null) unawaited(service.rebuildRooms());
  }, fireImmediately: true);
  return service;
});

/// How many messages a conversation loads at a time.
const messagePageSize = 40;

/// How far back a conversation's window currently reaches. Starts at one page
/// and grows as the person scrolls up (or jumps to an older message).
class MessageWindow extends Notifier<int> {
  MessageWindow(this.roomId);

  final String roomId;

  @override
  int build() => messagePageSize;

  void loadMore() => state += messagePageSize;

  /// Makes sure the window holds at least [count] messages.
  void ensureAtLeast(int count) {
    if (count > state) state = count + messagePageSize ~/ 2;
  }
}

final messageWindowProvider = NotifierProvider.autoDispose
    .family<MessageWindow, int, String>(MessageWindow.new);

/// The newest messages in a room (see [messageWindowProvider]), newest first.
/// Opening a long conversation reads one page, not its whole history.
final roomMessagesStreamProvider =
    StreamProvider.family<List<LocalMessage>, String>((ref, roomId) {
      final isarService = ref.watch(isarServiceProvider);
      final limit = ref.watch(messageWindowProvider(roomId));
      return isarService.watchMessagesForRoom(roomId, limit: limit);
    });

/// Messages quoted by replies that are older than the window, fetched on demand
/// so a quote never says "unavailable" just because it is far back. Keyed by the
/// comma-joined ids.
final quotedMessagesProvider = FutureProvider.autoDispose
    .family<Map<String, LocalMessage>, String>((ref, ids) {
      if (ids.isEmpty) return const {};
      return ref.watch(isarServiceProvider).getMessagesByIds(ids.split(','));
    });

/// Every conversation's summary row, most recent first.
///
/// Seeded from the database *synchronously*, so the very first frame of the
/// chat list already has every last message and unread count — like a
/// messenger, it shows what is on the phone at once and never loads it in.
/// After that it follows the database as messages arrive.
class ChatRoomsNotifier extends Notifier<List<LocalChatRoom>> {
  @override
  List<LocalChatRoom> build() {
    final service = ref.watch(isarServiceProvider);
    final changes = service
        .watchAllChatRooms(fireImmediately: false)
        .listen((rooms) => state = rooms);
    ref.onDispose(changes.cancel);
    return service.roomsNow();
  }
}

final chatRoomsProvider =
    NotifierProvider<ChatRoomsNotifier, List<LocalChatRoom>>(
      ChatRoomsNotifier.new,
    );

/// What a chat-list row needs to draw itself. A plain value, so a row rebuilds
/// only when *its own* conversation changes, not whenever any chat does.
class RoomPreview {
  const RoomPreview({
    required this.text,
    required this.timestamp,
    required this.senderId,
    required this.isImage,
    required this.isDeleted,
    required this.unread,
  });

  final String? text;
  final DateTime timestamp;
  final String senderId;
  final bool isImage;
  final bool isDeleted;
  final int unread;

  @override
  bool operator ==(Object other) =>
      other is RoomPreview &&
      other.text == text &&
      other.timestamp == timestamp &&
      other.senderId == senderId &&
      other.isImage == isImage &&
      other.isDeleted == isDeleted &&
      other.unread == unread;

  @override
  int get hashCode =>
      Object.hash(text, timestamp, senderId, isImage, isDeleted, unread);
}

RoomPreview _previewOf(LocalChatRoom r) => RoomPreview(
  text: r.lastMessageText,
  timestamp: r.lastMessageTimestamp,
  senderId: r.lastMessageSenderId,
  isImage: r.lastMessageIsImage,
  isDeleted: r.lastMessageDeleted,
  unread: r.unreadCount,
);

/// All previews by room id.
final roomPreviewsProvider = Provider<Map<String, RoomPreview>>((ref) {
  final rows = ref.watch(chatRoomsProvider);
  return {for (final r in rows) r.roomId: _previewOf(r)};
});

/// One conversation's preview, or null if it has no messages yet.
final roomPreviewProvider = Provider.family<RoomPreview?, String>(
  (ref, roomId) => ref.watch(roomPreviewsProvider.select((m) => m[roomId])),
);
