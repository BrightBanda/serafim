import 'package:isar_community/isar.dart';

part 'local_chat_message.g.dart';

/// New values go at the END: the index is what is stored on the device.
/// `audio` is a voice note; `audioFile` is a music/audio file someone picked
/// (MP3, M4A, …); `sticker` keeps its sticker id in [textContent].
/// Stored by position: add new kinds at the end only.
enum MessageType { text, image, video, audio, sticker, post, audioFile }

enum MessageStatus { sending, sent, delivered, read, failed }

@collection
class LocalMessage {
  Id id = Isar.autoIncrement; // Auto-incrementing internal integer ID

  @Index(unique: true, replace: true)
  late String messageId; // Server-assigned or client-assigned UUID string

  @Index()
  late String roomId;

  late String senderId;

  /// The other person in a 1:1 chat, or the group id in a group chat.
  late String recipientId;

  /// Set for group messages (the room id is then `group_<id>`).
  @Index()
  String? groupId;

  String? textContent;

  String?
  localMediaPath; // Path on physical device: /storage/emulated/.../photo.jpg

  @enumerated
  MessageType type = MessageType.text;

  @enumerated
  MessageStatus status = MessageStatus.sending;

  /// Set when the sender edited the text after sending.
  DateTime? editedAt;

  /// Voice notes, videos and audio files: the server's media id, once
  /// uploaded.
  String? mediaRemoteId;

  /// Voice notes (and videos/audio files when known): length in
  /// milliseconds.
  int? durationMs;

  /// Videos and audio files: the name it had on the sender's device.
  String? fileName;

  /// Videos and audio files: size in bytes, shown before downloading.
  int? fileSize;

  /// Voice notes: a coarse loudness outline (0–31 per bar) for the waveform.
  List<int>? waveform;

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

  /// This copy is a message the person forwarded to another chat. Only the
  /// sender's own copy carries it; the people it was sent to see an ordinary
  /// message.
  bool forwarded = false;

  @Index()
  late DateTime timestamp;
}

/// Whether [type] is a video or audio file (uploaded to storage, fetched on
/// request), as opposed to a voice note or a picture.
bool isChatFile(MessageType type) =>
    type == MessageType.video || type == MessageType.audioFile;
