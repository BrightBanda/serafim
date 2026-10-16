import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';

class IsarService {
  late Future<Isar> db;

  /// Whose phone this is. Unread counts are about *this* person's inbox, and a
  /// conversation only gets a summary row if they are part of it. Set when
  /// someone signs in; without it the summary rows are left alone.
  String? accountId;

  IsarService() {
    db = _initDB();
  }

  /// Uses an already-open database (tests).
  IsarService.withDb(Future<Isar> database) {
    db = database;
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
      await _syncRoom(isar, message.roomId);
    });
  }

  /// Watch a chat room's messages, newest first. With [limit] only that many of
  /// the newest are loaded (and watched), so opening a long conversation does
  /// not read its whole history; ask for a larger window to go further back.
  Stream<List<LocalMessage>> watchMessagesForRoom(
    String roomId, {
    int? limit,
  }) async* {
    final isar = await db;
    final newestFirst = isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .isHiddenForMeEqualTo(false)
        .sortByTimestampDesc();
    yield* limit == null
        ? newestFirst.watch(fireImmediately: true)
        : newestFirst.limit(limit).watch(fireImmediately: true);
  }

  /// A few specific messages by id (e.g. the originals that replies quote,
  /// which may be older than the window being shown).
  Future<Map<String, LocalMessage>> getMessagesByIds(
    Iterable<String> ids,
  ) async {
    final isar = await db;
    final found = <String, LocalMessage>{};
    for (final id in ids.toSet()) {
      final m = await isar.localMessages
          .filter()
          .messageIdEqualTo(id)
          .findFirst();
      if (m != null) found[id] = m;
    }
    return found;
  }

  /// How many visible messages in [roomId] are as new as [at] or newer — i.e.
  /// how big the window must be to include the message sent at [at].
  Future<int> countMessagesAtOrAfter(String roomId, DateTime at) async {
    final isar = await db;
    return isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .isHiddenForMeEqualTo(false)
        .timestampGreaterThan(at, include: true)
        .count();
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
        await _syncRoom(isar, msg.roomId);
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
      if (unread.isNotEmpty) await _syncRoom(isar, roomId);
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

  /// The sender edited a message. No-op for unknown/deleted rows.
  Future<void> applyEdit(
    String messageId,
    String content,
    DateTime editedAt,
  ) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null || msg.isDeleted) return;
      msg.textContent = content;
      msg.editedAt = editedAt;
      await isar.localMessages.put(msg);
      await _syncRoom(isar, msg.roomId);
    });
  }

  /// A message was deleted for everyone: wipe its content and image file but
  /// keep the row so history and ordering stay intact.
  Future<void> applyDelete(String messageId) async {
    final isar = await db;
    String? mediaPath;
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null || msg.isDeleted) return;
      mediaPath = msg.localMediaPath;
      msg.isDeleted = true;
      msg.textContent = null;
      msg.localMediaPath = null;
      msg.type = MessageType.text;
      await isar.localMessages.put(msg);
      await _syncRoom(isar, msg.roomId);
    });
    if (mediaPath != null) {
      try {
        final file = File(mediaPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// "Delete for me": clear the message from this device (text and image file)
  /// but keep a hidden tombstone so it can't reappear.
  Future<void> hideMessageForMe(String messageId) async {
    final isar = await db;
    String? mediaPath;
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null) return;
      mediaPath = msg.localMediaPath;
      msg.isHiddenForMe = true;
      msg.textContent = null;
      msg.localMediaPath = null;
      msg.type = MessageType.text;
      await isar.localMessages.put(msg);
      await _syncRoom(isar, msg.roomId);
    });
    await _deleteFile(mediaPath);
  }

  /// Retention: removes messages older than [cutoff] and their image files.
  /// Returns how many were removed.
  Future<int> purgeOlderThan(DateTime cutoff) async {
    final isar = await db;
    final paths = <String>[];
    var removed = 0;
    await isar.writeTxn(() async {
      final old = await isar.localMessages
          .filter()
          .timestampLessThan(cutoff)
          .findAll();
      for (final m in old) {
        final path = m.localMediaPath;
        if (path != null) paths.add(path);
      }
      removed = await isar.localMessages.deleteAll(
        old.map((m) => m.id).toList(),
      );
      for (final roomId in old.map((m) => m.roomId).toSet()) {
        await _syncRoom(isar, roomId);
      }
    });
    for (final path in paths) {
      await _deleteFile(path);
    }
    return removed;
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Removes a message that only exists on this device.
  Future<void> deleteLocalMessage(String messageId) async {
    final isar = await db;
    String? mediaPath;
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null) return;
      mediaPath = msg.localMediaPath;
      await isar.localMessages.delete(msg.id);
      await _syncRoom(isar, msg.roomId);
    });
    if (mediaPath != null) {
      try {
        final file = File(mediaPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Ids of the newest server-known messages in either direction, sent to the
  /// server after reconnecting so it can report anything that changed (status,
  /// edits, deletions) while this device was offline.
  Future<List<String>> getRecentSyncIds(String myId, {int limit = 300}) async {
    final isar = await db;
    final msgs = await isar.localMessages
        .filter()
        .senderIdEqualTo(myId)
        .or()
        .recipientIdEqualTo(myId)
        .sortByTimestampDesc()
        .limit(limit)
        .findAll();
    return msgs.map((m) => m.messageId).toList();
  }

  /// Ids of every user this account has exchanged messages with.
  Stream<List<String>> watchConversationPeerIds(String myId) async* {
    final isar = await db;
    yield* isar.localMessages.where().watchLazy(fireImmediately: true).asyncMap(
      (_) async {
        final latest = await isar.localMessages
            .where()
            .distinctByRoomId()
            .findAll();
        return latest
            .map((m) => m.senderId == myId ? m.recipientId : m.senderId)
            .toSet()
            .toList();
      },
    );
  }

  // ==========================================
  // CHAT ROOMS MANAGEMENT
  // ==========================================

  /// Brings one conversation's summary row up to date with its messages: the
  /// newest visible message and how many incoming ones are unread. Must run
  /// inside a write transaction, right after the change that made it stale.
  Future<void> _syncRoom(Isar isar, String roomId) async {
    final me = accountId;
    if (me == null) return;

    final latest = await isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .isHiddenForMeEqualTo(false)
        .sortByTimestampDesc()
        .findFirst();

    // No visible messages left, or a conversation this account isn't part of
    // (the database is shared by everyone who has signed in on this phone).
    if (latest == null || (latest.senderId != me && latest.recipientId != me)) {
      await isar.localChatRooms.deleteByRoomId(roomId);
      return;
    }

    final unread = await isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .isHiddenForMeEqualTo(false)
        .recipientIdEqualTo(me)
        .not()
        .statusEqualTo(MessageStatus.read)
        .count();

    final room =
        await isar.localChatRooms.getByRoomId(roomId) ?? LocalChatRoom()
          ..roomId = roomId;
    room
      ..peerUserId = latest.senderId == me
          ? latest.recipientId
          : latest.senderId
      ..lastMessageText = latest.isDeleted ? null : latest.textContent
      ..lastMessageSenderId = latest.senderId
      ..lastMessageIsImage =
          latest.type == MessageType.image && !latest.isDeleted
      ..lastMessageDeleted = latest.isDeleted
      ..lastMessageTimestamp = latest.timestamp
      ..unreadCount = unread;
    await isar.localChatRooms.putByRoomId(room);
  }

  /// Rebuilds every conversation's summary row from the messages. Run when
  /// someone signs in: it fills in conversations that existed before summary
  /// rows did, repairs anything that drifted, and drops rows that belong to a
  /// previous account on this phone.
  Future<void> rebuildRooms() async {
    final isar = await db;
    if (accountId == null) return;
    await isar.writeTxn(() async {
      await isar.localChatRooms.clear();
      final rooms = await isar.localMessages
          .where()
          .distinctByRoomId()
          .findAll();
      for (final m in rooms) {
        await _syncRoom(isar, m.roomId);
      }
    });
  }

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
