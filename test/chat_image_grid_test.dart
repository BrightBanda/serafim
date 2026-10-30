import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';

LocalMessage _image(String id, DateTime timestamp, {String sender = 'me'}) =>
    LocalMessage()
      ..messageId = id
      ..roomId = 'room'
      ..senderId = sender
      ..recipientId = 'peer'
      ..type = MessageType.image
      ..localMediaPath = '/$id.jpg'
      ..timestamp = timestamp;

void main() {
  test(
    'adjacent image burst groups by sender while other messages split it',
    () {
      final now = DateTime.utc(2026, 10, 29, 12);
      final newer = _image('newer', now);
      final older = _image('older', now.subtract(const Duration(seconds: 1)));
      final text = LocalMessage()
        ..messageId = 'text'
        ..roomId = 'room'
        ..senderId = 'me'
        ..recipientId = 'peer'
        ..type = MessageType.text
        ..timestamp = now.subtract(const Duration(seconds: 2));
      final otherSender = _image(
        'other',
        now.subtract(const Duration(seconds: 3)),
        sender: 'peer',
      );

      final groups = groupImagesForDisplay([newer, older, text, otherSender]);

      expect(groups.map((group) => group.map((m) => m.messageId).toList()), [
        ['newer', 'older'],
        ['text'],
        ['other'],
      ]);
    },
  );

  test('separated image bursts remain separate', () {
    final now = DateTime.utc(2026, 10, 29, 12);
    final groups = groupImagesForDisplay([
      _image('new', now),
      _image('old', now.subtract(const Duration(seconds: 9))),
    ]);

    expect(groups, hasLength(2));
  });
}
