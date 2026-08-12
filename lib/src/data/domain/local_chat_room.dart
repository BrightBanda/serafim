import 'package:isar/isar.dart';

part 'local_chat_room.g.dart';

@collection
class LocalChatRoom {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String roomId;

  late String peerUserId; // ID of the other user in 1-on-1 chat

  late String peerDisplayName;

  String? peerAvatarUrl;

  String? lastMessageText;

  late DateTime lastMessageTimestamp;

  int unreadCount = 0;
}
