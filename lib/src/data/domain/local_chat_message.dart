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

  @Index()
  late DateTime timestamp;
}
