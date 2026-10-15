import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';

class RoomSummary {
  const RoomSummary({this.latest, this.unreadCount = 0});

  final LocalMessage? latest;
  final int unreadCount;
}

class IsarService {
  late Future<Isar> db;

  IsarService() {
    db = _initDB();
  }

  Future<Isar> _initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    if (Isar.instanceNames.isEmpty) {
      return await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        inspector: true, // Enables Isar Inspector in dev environment
      );
    }
    return Future.value(Isar.getInstance());
  }

  // ==========================================
  // CHAT MESSAGES MANAGEMENT
  // ==========================================

  /// Save or update a single message
  Future<void> saveMessage(LocalMessage message) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.localMessages.put(message);
    });
  }

  /// Watch real-time message stream for a specific chat room
  Stream<List<LocalMessage>> watchMessagesForRoom(String roomId) async* {
    final isar = await db;
    yield* isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .sortByTimestampDesc()
        .watch(fireImmediately: true);
  }

  /// Update the delivery/read status and timestamp of a message locally
  // lib/src/data/local/isar_service.dart

  /// Update the delivery/read status and timestamp of a message locally.
  /// Returns true if a matching row was found and updated, false otherwise.
  Future<bool> updateMessageStatus(
    String messageId,
    MessageStatus status, {
    String? newMessageId,
    DateTime? newTimestamp,
  }) async {
    final isar = await db;
    var found = false;
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg != null) {
        found = true;
        // Statuses only move forward. A late 'delivered' (or a stale sync
        // reply) must never knock a 'read' message back down.
        final regresses =
            status != MessageStatus.failed &&
            msg.status != MessageStatus.failed &&
            status.index < msg.status.index;
        if (!regresses) msg.status = status;
        if (newMessageId != null &&
            newMessageId.isNotEmpty &&
            newMessageId != messageId) {
          msg.messageId = newMessageId;
        }
        if (newTimestamp != null) {
          msg.timestamp = newTimestamp;
        }
        await isar.localMessages.put(msg);
      }
    });
    return found;
  }

  Future<LocalMessage?> getMessageById(String messageId) async {
    final isar = await db;
    return isar.localMessages.filter().messageIdEqualTo(messageId).findFirst();
  }

  /// Marks every unread incoming message in [roomId] as read locally and
  /// flags it as still owing a read receipt to the server. Returns their ids.
  Future<List<String>> markRoomRead(String roomId, String myId) async {
    final isar = await db;
    var ids = <String>[];
    await isar.writeTxn(() async {
      final unread = await isar.localMessages
          .filter()
          .roomIdEqualTo(roomId)
          .recipientIdEqualTo(myId)
          .not()
          .statusEqualTo(MessageStatus.read)
          .findAll();
      for (final msg in unread) {
        msg.status = MessageStatus.read;
        msg.readAckPending = true;
      }
      await isar.localMessages.putAll(unread);
      ids = unread.map((m) => m.messageId).toList();
    });
    return ids;
  }

  /// Incoming messages the user has read but the server hasn't been told about.
  Future<List<LocalMessage>> getPendingReadAcks(String myId) async {
    final isar = await db;
    return isar.localMessages
        .filter()
        .recipientIdEqualTo(myId)
        .readAckPendingEqualTo(true)
        .findAll();
  }

  Future<void> clearReadAckPending(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final isar = await db;
    await isar.writeTxn(() async {
      final msgs = <LocalMessage>[];
      for (final id in messageIds) {
        final msg = await isar.localMessages
            .filter()
            .messageIdEqualTo(id)
            .findFirst();
        if (msg != null) {
          msg.readAckPending = false;
          msgs.add(msg);
        }
      }
      await isar.localMessages.putAll(msgs);
    });
  }

  /// Outgoing messages the server has accepted but that aren't 'read' yet —
  /// the ones whose status updates may have been missed while offline.
  Future<List<String>> getUnsettledOutgoingIds(String myId) async {
    final isar = await db;
    final msgs = await isar.localMessages
        .filter()
        .senderIdEqualTo(myId)
        .group(
          (q) => q
              .statusEqualTo(MessageStatus.sent)
              .or()
              .statusEqualTo(MessageStatus.delivered),
        )
        .findAll();
    return msgs.map((m) => m.messageId).toList();
  }

  /// Newest message in a room plus how many incoming messages are unread.
  Stream<RoomSummary> watchRoomSummary(String roomId, String myId) async* {
    final isar = await db;
    yield* isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .watchLazy(fireImmediately: true)
        .asyncMap((_) async {
          final latest = await isar.localMessages
              .filter()
              .roomIdEqualTo(roomId)
              .sortByTimestampDesc()
              .findFirst();
          final unread = await isar.localMessages
              .filter()
              .roomIdEqualTo(roomId)
              .recipientIdEqualTo(myId)
              .not()
              .statusEqualTo(MessageStatus.read)
              .count();
          return RoomSummary(latest: latest, unreadCount: unread);
        });
  }

  // ==========================================
  // CHAT ROOMS MANAGEMENT
  // ==========================================

  /// Save/Update a chat room preview
  Future<void> saveChatRoom(LocalChatRoom room) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.localChatRooms.put(room);
    });
  }

  Future<List<LocalMessage>> getPendingMessages() async {
    final isar = await db;
    return await isar.localMessages
        .filter()
        .statusEqualTo(MessageStatus.sending)
        .findAll();
  }

  /// Watch real-time stream of all active chat rooms sorted by latest activity
  Stream<List<LocalChatRoom>> watchAllChatRooms() async* {
    final isar = await db;
    yield* isar.localChatRooms.where().sortByLastMessageTimestampDesc().watch(
      fireImmediately: true,
    );
  }
}
