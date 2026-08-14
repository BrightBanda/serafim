import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';

// Single instance of IsarService
final isarServiceProvider = Provider<IsarService>((ref) {
  return IsarService();
});

// Stream provider for listening to messages in a specific room
final roomMessagesStreamProvider =
    StreamProvider.family<List<LocalMessage>, String>((ref, roomId) {
      final isarService = ref.watch(isarServiceProvider);
      return isarService.watchMessagesForRoom(roomId);
    });

// Stream provider for listening to all recent chat rooms
final chatRoomsStreamProvider = StreamProvider<List<LocalChatRoom>>((ref) {
  final isarService = ref.watch(isarServiceProvider);
  return isarService.watchAllChatRooms();
});
