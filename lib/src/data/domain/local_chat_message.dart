import 'package:isar_community/isar.dart';

part 'local_chat_message.g.dart';

enum MessageType { text, image, video, audio }

enum MessageStatus { sending, sent, delivered, read, failed }

@collection
class LocalMessage {
  Id id = Isar.autoIncrement; // Auto-incrementing internal integer ID

  @Index(unique: true, replace: true)
  late String messageId; // Server-assigned or client-assigned UUID string

  @Index()
  late String roomId;

  late String senderId;

  late String recipientId;

  String? textContent;

  String?
  localMediaPath; // Path on physical device: /storage/emulated/.../photo.jpg

  @enumerated
  MessageType type = MessageType.text;

  @enumerated
  MessageStatus status = MessageStatus.sending;

  /// Set when the sender edited the text after sending.
  DateTime? editedAt;

  /// The message this one answers (its server id), if any.
  String? replyToId;

  /// "Delete for me": hidden from this device only. The row stays (content
  /// wiped) so a re-push from the server can never bring it back.
  bool isHiddenForMe = false;

  /// Deleted for everyone. The row stays as a tombstone (content wiped) so
  /// ordering and history are unchanged.
  bool isDeleted = false;

  /// Incoming messages only: the user has seen this message locally but the
  /// server has not yet been told (socket was down). Flushed on reconnect.
  bool readAckPending = false;

  @Index()
  late DateTime timestamp;
}
