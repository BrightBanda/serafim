import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';

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
        msg.status = status;
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
