import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';

void main() {
  group('ChatViewModel Room ID Calculation', () {
    test('room ID is deterministic and order-independent', () {
      final userA = 'user-1';
      final userB = 'user-2';

      final roomId1 = ChatViewModel.buildRoomId(userA, userB);
      final roomId2 = ChatViewModel.buildRoomId(userB, userA);

      expect(roomId1, equals(roomId2));
      expect(roomId1, equals('user-1_user-2'));
      expect(roomId2, equals('user-1_user-2'));
    });

    test('room ID uses alphabetical order', () {
      final roomId1 = ChatViewModel.buildRoomId('zebra', 'apple');
      final roomId2 = ChatViewModel.buildRoomId('apple', 'zebra');

      expect(roomId1, equals('apple_zebra'));
      expect(roomId2, equals('apple_zebra'));
    });

    test('room ID handles UUID format correctly when first is larger', () {
      final uuid1 = '550e8400-e29b-41d4-a716-446655440000';
      final uuid2 = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

      final roomId1 = ChatViewModel.buildRoomId(uuid1, uuid2);
      final roomId2 = ChatViewModel.buildRoomId(uuid2, uuid1);

      expect(roomId1, equals(roomId2));
      // uuid2 comes first alphabetically (because '6' < '5')
      expect(roomId1, equals('550e8400-e29b-41d4-a716-446655440000_6ba7b810-9dad-11d1-80b4-00c04fd430c8'));
    });

    test('room ID handles same user correctly', () {
      final roomId = ChatViewModel.buildRoomId('same-user-id', 'same-user-id');
      expect(roomId, equals('same-user-id_same-user-id'));
    });
  });
}