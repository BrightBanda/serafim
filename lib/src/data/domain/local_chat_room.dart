import 'package:isar_community/isar.dart';

part 'local_chat_room.g.dart';

/// One row per conversation, kept up to date by [IsarService] whenever a
/// message in it changes. The chat list reads these instead of working out the
/// latest message and unread count for every chat on every change, so it stays
/// fast however much history there is.
@collection
class LocalChatRoom {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String roomId;

  /// ID of the other person in this 1-on-1 chat.
  String peerUserId = '';

  // The peer's name and photo are looked up from the saved people list, so they
  // stay current; these two are kept only for older rows.
  String peerDisplayName = '';
  String? peerAvatarUrl;

  /// Newest message you can see (hidden-for-me ones are skipped).
  String? lastMessageText;
  String lastMessageSenderId = '';
  bool lastMessageIsImage = false;
  bool lastMessageDeleted = false;
  DateTime lastMessageTimestamp = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  /// Incoming messages you have not read yet.
  int unreadCount = 0;
}
