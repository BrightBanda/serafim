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

  /// The open database, once it is open. Lets the chat list read what is on
  /// the phone *synchronously* on its very first frame, instead of showing an
  /// empty list for a moment while a stream delivers it.
  Isar? get openNow {
    final isar = Isar.getInstance();
    return isar != null && isar.isOpen ? isar : null;
  }

  /// Every conversation's summary row, newest first, read right now. Empty
  /// until the database is open (see [openNow]).
  List<LocalChatRoom> roomsNow() =>
      openNow?.localChatRooms
          .where()
          .sortByLastMessageTimestampDesc()
          .findAllSync() ??
      const [];

  /// Ids of everyone [myId] has a 1:1 conversation with, read right now.
  List<String> peerIdsNow(String myId) {
    final isar = openNow;
    if (isar == null) return const [];
    return _peerIdsOf(
      isar.localMessages
          .filter()
          .groupIdIsNull()
          .distinctByRoomId()
          .findAllSync(),
      myId,
    );
  }

  static List<String> _peerIdsOf(List<LocalMessage> latest, String myId) =>
      latest
          .map((m) => m.senderId == myId ? m.recipientId : m.senderId)
          .toSet()
          .toList();

  Future<Isar> _initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    if (Isar.instanceNames.isEmpty) {
      return await Isar.open(
        _schemas,
        directory: dir.path,
        inspector: true, // Enables Isar Inspector in dev environment
      );
    }
    return Future.value(Isar.getInstance());
  }

  // ==========================================
  // BACKUP AND RESTORE
  // ==========================================

  static const _schemas = [LocalMessageSchema, LocalChatRoomSchema];

  /// Writes a consistent copy of the whole database to [path] (any existing
  /// file there is replaced). Safe to run while the app is in use.
  Future<void> snapshotTo(String path) async {
    final isar = await db;
    final file = File(path);
    if (await file.exists()) await file.delete();
    await isar.copyToFile(path);
  }

  /// Whether [path] is a database this version of the app can read. Opened
  /// under a throwaway name, so the live database is not touched.
  Future<bool> isValidBackup(String path) async {
    final tmp = await Directory.systemTemp.createTemp('serafim_check_');
    try {
      await File(path).copy('${tmp.path}/check.isar');
      final check = await Isar.open(
        _schemas,
        directory: tmp.path,
        name: 'check',
      );
      await check.close();
      return true;
    } catch (_) {
      return false;
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  /// Replaces the database with the one at [path]. The current one is closed
  /// first and kept as `<name>.before-restore` until the swap has worked, so a
  /// failed restore puts everything back. Callers should check
  /// [isValidBackup] first.
  Future<void> restoreFrom(String path) async {
    final dir = await getApplicationDocumentsDirectory();
    final live = File('${dir.path}/default.isar');
    final aside = File('${dir.path}/default.isar.before-restore');
    final current = await db;
    await current.close();
    try {
      if (await aside.exists()) await aside.delete();
      if (await live.exists()) await live.rename(aside.path);
      await File(path).copy(live.path);
      db = _initDB();
      await db;
      if (await aside.exists()) await aside.delete();
    } catch (_) {
      if (await live.exists()) await live.delete();
      if (await aside.exists()) await aside.rename(live.path);
      db = _initDB();
      rethrow;
    }
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

  /// Records where a voice note's audio is: its server id once uploaded,
  /// and/or the local file once downloaded.
  Future<void> updateMedia(
    String messageId, {
    String? mediaRemoteId,
    String? localMediaPath,
    String? thumbnailPath,
  }) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null || msg.isDeleted || msg.isHiddenForMe) return;
      if (mediaRemoteId != null) msg.mediaRemoteId = mediaRemoteId;
      if (localMediaPath != null) msg.localMediaPath = localMediaPath;
      if (thumbnailPath != null) msg.thumbnailPath = thumbnailPath;
      await isar.localMessages.put(msg);
    });
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
      // In a group, "incoming" is anything someone else sent; groups have no
      // read receipts, so nothing is owed to the server.
      final group = _isGroupRoom(roomId);
      final base = isar.localMessages.filter().roomIdEqualTo(roomId);
      final unread =
          await (group
                  ? base.not().senderIdEqualTo(myId)
                  : base.recipientIdEqualTo(myId))
              .not()
              .statusEqualTo(MessageStatus.read)
              .findAll();
      for (final msg in unread) {
        msg.status = MessageStatus.read;
        msg.readAckPending = !group;
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

  /// The sender edited a message. No-op for unknown/deleted rows, and for ones
  /// hidden on this device (deleted for me, or a cleared chat): an edit must
  /// not bring their text back.
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
      if (msg == null || msg.isDeleted || msg.isHiddenForMe) return;
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
    var files = const <String>[];
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null || msg.isDeleted) return;
      files = _filesOf(msg);
      msg.isDeleted = true;
      msg.textContent = null;
      msg.localMediaPath = null;
      msg.thumbnailPath = null;
      msg.type = MessageType.text;
      await isar.localMessages.put(msg);
      await _syncRoom(isar, msg.roomId);
    });
    await _deleteFiles(files);
  }

  /// "Delete for me": clear the message from this device (text and image file)
  /// but keep a hidden tombstone so it can't reappear.
  Future<void> hideMessageForMe(String messageId) async {
    final isar = await db;
    var files = const <String>[];
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null) return;
      files = _filesOf(msg);
      msg.isHiddenForMe = true;
      msg.textContent = null;
      msg.localMediaPath = null;
      msg.thumbnailPath = null;
      msg.type = MessageType.text;
      await isar.localMessages.put(msg);
      await _syncRoom(isar, msg.roomId);
    });
    await _deleteFiles(files);
  }

  /// "Clear chat": every message in [roomId] goes from this device, with its
  /// files. Like [hideMessageForMe], messages the server knows about keep a
  /// hidden tombstone, so a resync cannot bring them back; ones that never
  /// left this phone (sending or failed) are removed outright, so they are not
  /// retried either. Nobody else's copy is touched.
  Future<void> clearRoomForMe(String roomId) async {
    final isar = await db;
    final paths = <String>[];
    await isar.writeTxn(() async {
      final all = await isar.localMessages
          .filter()
          .roomIdEqualTo(roomId)
          .findAll();
      final unsent = <int>[];
      final hidden = <LocalMessage>[];
      for (final m in all) {
        paths.addAll(_filesOf(m));
        if (m.status == MessageStatus.sending ||
            m.status == MessageStatus.failed) {
          unsent.add(m.id);
        } else if (!m.isHiddenForMe) {
          hidden.add(
            m
              ..isHiddenForMe = true
              ..textContent = null
              ..localMediaPath = null
              ..thumbnailPath = null
              ..type = MessageType.text,
          );
        }
      }
      await isar.localMessages.deleteAll(unsent);
      await isar.localMessages.putAll(hidden);
      await _syncRoom(isar, roomId);
    });
    await _deleteFiles(paths);
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
        paths.addAll(_filesOf(m));
      }
      removed = await isar.localMessages.deleteAll(
        old.map((m) => m.id).toList(),
      );
      for (final roomId in old.map((m) => m.roomId).toSet()) {
        await _syncRoom(isar, roomId);
      }
    });
    await _deleteFiles(paths);
    return removed;
  }

  /// The files on this device that belong to [m]: its media and preview.
  static List<String> _filesOf(LocalMessage m) => [
    ?m.localMediaPath,
    ?m.thumbnailPath,
  ];

  Future<void> _deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Removes a message that only exists on this device.
  Future<void> deleteLocalMessage(String messageId) async {
    final isar = await db;
    var files = const <String>[];
    await isar.writeTxn(() async {
      final msg = await isar.localMessages
          .filter()
          .messageIdEqualTo(messageId)
          .findFirst();
      if (msg == null) return;
      files = _filesOf(msg);
      await isar.localMessages.delete(msg.id);
      await _syncRoom(isar, msg.roomId);
    });
    await _deleteFiles(files);
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
  ///
  /// With [fireImmediately] false it only reports *changes* — for a caller
  /// that already has the current answer from [peerIdsNow].
  Stream<List<String>> watchConversationPeerIds(
    String myId, {
    bool fireImmediately = true,
  }) async* {
    final isar = await db;
    yield* isar.localMessages
        .where()
        .watchLazy(fireImmediately: fireImmediately)
        .asyncMap(
          (_) async => _peerIdsOf(
            // 1:1 conversations only; groups are listed from the group list.
            await isar.localMessages
                .filter()
                .groupIdIsNull()
                .distinctByRoomId()
                .findAll(),
            myId,
          ),
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

    final group = _isGroupRoom(roomId);
    // No visible messages left, or a conversation this account isn't part of
    // (the database is shared by everyone who has signed in on this phone).
    // Group membership is checked against the account's group list instead.
    if (latest == null ||
        (!group && latest.senderId != me && latest.recipientId != me)) {
      await isar.localChatRooms.deleteByRoomId(roomId);
      return;
    }

    final visible = isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .isHiddenForMeEqualTo(false);
    final unread =
        await (group
                ? visible.not().senderIdEqualTo(me)
                : visible.recipientIdEqualTo(me))
            .not()
            .statusEqualTo(MessageStatus.read)
            .count();

    final room =
        await isar.localChatRooms.getByRoomId(roomId) ?? LocalChatRoom()
          ..roomId = roomId;
    room
      ..peerUserId = group
          ? (latest.groupId ?? '')
          : latest.senderId == me
          ? latest.recipientId
          : latest.senderId
      ..lastMessageText = latest.isDeleted ? null : previewTextOf(latest)
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

  /// Newest message time in [roomId] (for catching up on a group).
  Future<DateTime?> latestTimestamp(String roomId) async {
    final isar = await db;
    final m = await isar.localMessages
        .filter()
        .roomIdEqualTo(roomId)
        .sortByTimestampDesc()
        .findFirst();
    return m?.timestamp;
  }

  /// Removes a whole conversation from this device (e.g. a group you left
  /// or were removed from), with its files.
  Future<void> deleteRoom(String roomId) async {
    final isar = await db;
    final paths = <String>[];
    await isar.writeTxn(() async {
      final all = await isar.localMessages
          .filter()
          .roomIdEqualTo(roomId)
          .findAll();
      for (final m in all) {
        paths.addAll(_filesOf(m));
      }
      await isar.localMessages.deleteAll(all.map((m) => m.id).toList());
      await isar.localChatRooms.deleteByRoomId(roomId);
    });
    await _deleteFiles(paths);
  }

  static bool _isGroupRoom(String roomId) => roomId.startsWith('group_');

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
  Stream<List<LocalChatRoom>> watchAllChatRooms({
    bool fireImmediately = true,
  }) async* {
    final isar = await db;
    yield* isar.localChatRooms.where().sortByLastMessageTimestampDesc().watch(
      fireImmediately: fireImmediately,
    );
  }
}

/// What the chat list shows for [m]: its text, or a label for messages whose
/// "text" is not meant to be read (a sticker's id, a voice note).
String? previewTextOf(LocalMessage m) => switch (m.type) {
  MessageType.sticker => '🙂 Sticker',
  MessageType.post => '📝 Post',
  MessageType.audio => '🎤 Voice message',
  MessageType.video => '🎬 Video',
  MessageType.audioFile => '🎵 ${m.fileName ?? 'Audio'}',
  _ => m.textContent,
};
