import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/core/platform/chat_notifications.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSocket extends WebSocketService {
  final sent = <Map<String, dynamic>>[];
  @override
  bool sendMessage(Map<String, dynamic> payload) {
    sent.add(payload);
    return true;
  }
}

class FakeReplyQueue implements NotificationReplyQueue {
  FakeReplyQueue(this.replies);
  final List<QueuedReply> replies;

  @override
  Future<List<QueuedReply>> queuedReplies() async => List.of(replies);

  @override
  Future<void> forgetReply(String clientId) async =>
      replies.removeWhere((r) => r.clientId == clientId);
}

void main() {
  group('reading a chat push', () {
    test('a 1:1 message the app draws', () {
      final push = ChatPush.fromData({
        'type': 'message',
        'message_id': 'm1',
        'sender_id': 'alice',
        'from_id': 'alice',
        'recipient_id': 'bob',
        'title': 'Alice A',
        'body': 'are you free?',
        'sender_name': 'Alice A',
        'text': 'are you free?',
        'reply': 'signed-link',
      })!;
      expect(push.isGroup, isFalse);
      expect(push.target, 'alice');
      expect(push.roomId, ChatViewModel.buildRoomId('bob', 'alice'));
      expect(push.text, 'are you free?');
      expect(push.replyToken, 'signed-link');
    });

    test('a group message is filed under the group, sender kept apart', () {
      final push = ChatPush.fromData({
        'type': 'group_message',
        'message_id': 'm2',
        'group_id': 'g1',
        'from_id': 'alice',
        'recipient_id': 'bob',
        'title': 'Crew',
        'sender_name': 'Alice A',
        'text': 'hi all',
      })!;
      expect(push.isGroup, isTrue);
      expect(push.target, 'g1');
      expect(push.roomId, 'group_g1');
      expect(push.senderName, 'Alice A');
      expect(push.replyToken, isNull); // no signing key on the server
    });

    test('system notifications and other pushes are left to the system', () {
      // An older server (or a system-style phone): no from/recipient ids.
      expect(
        ChatPush.fromData({
          'type': 'message',
          'sender_id': 'alice',
          'message_id': 'm1',
        }),
        isNull,
      );
      expect(
        ChatPush.fromData({'type': 'friend_request', 'notification_id': 'n'}),
        isNull,
      );
      expect(
        ChatPush.fromData({
          'type': 'group_message',
          'message_id': 'm',
          'from_id': 'a',
          'recipient_id': 'b',
        }),
        isNull,
      );
    });
  });

  test('each conversation keeps one notification id, the same every run', () {
    final a = notificationIdFor('alice_bob');
    expect(notificationIdFor('alice_bob'), a);
    expect(notificationIdFor('group_g1'), isNot(a));
    expect(a, inInclusiveRange(0, 0x7fffffff));
    // Fixed by the algorithm, not by this process.
    expect(notificationIdFor(''), 0x811c9dc5 & 0x7fffffff);
  });

  test('queued replies and tapped notifications survive the trip', () {
    final reply = QueuedReply(
      clientId: 'n1',
      userId: 'bob',
      target: 'g1',
      isGroup: true,
      text: 'on my way',
      at: DateTime.utc(2026, 11, 4, 9),
    );
    final back = QueuedReply.fromJson(reply.toJson())!;
    expect(back.clientId, 'n1');
    expect(back.isGroup, isTrue);
    expect(back.at, reply.at);
    expect(QueuedReply.fromJson({'client_id': 'x'}), isNull);

    final tap = ChatNotifications.targetOf('{"target":"alice","room":"r"}')!;
    expect(tap.target, 'alice');
    expect(tap.isGroup, isFalse);
    expect(ChatNotifications.targetOf('not json'), isNull);
  });

  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  group('replies typed into notifications', () {
    late Directory dir;
    late Isar isar;
    late FakeSocket socket;
    late FakeReplyQueue queue;
    late ProviderContainer c;

    setUpAll(() async {
      if (haveLib) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      }
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('notif_reply');
      isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 'n${DateTime.now().microsecondsSinceEpoch}',
      );
      final service = IsarService.withDb(Future.value(isar))..accountId = 'me';
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      socket = FakeSocket();
      queue = FakeReplyQueue([
        QueuedReply(
          clientId: 'n2',
          userId: 'me',
          target: 'g1',
          isGroup: true,
          text: 'see you all',
          at: DateTime.utc(2026, 11, 4, 9, 1),
        ),
        QueuedReply(
          clientId: 'n1',
          userId: 'me',
          target: 'alice',
          text: 'on my way',
          at: DateTime.utc(2026, 11, 4, 9),
        ),
        QueuedReply(
          clientId: 'n3',
          userId: 'someone-who-signed-out',
          target: 'alice',
          text: 'not mine',
          at: DateTime.utc(2026, 11, 4, 9, 2),
        ),
      ]);
      c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          isarServiceProvider.overrideWithValue(service),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketEventsProvider.overrideWith((ref) => const Stream.empty()),
          webSocketServiceProvider.overrideWithValue(socket),
          notificationReplyQueueProvider.overrideWithValue(queue),
        ],
      );
    });

    tearDown(() async {
      c.dispose();
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    test('go into their chats and are sent under the same id', () async {
      await c.read(chatViewModelProvider.notifier).importNotificationReplies();

      final dm = await isar.localMessages
          .filter()
          .messageIdEqualTo('n1')
          .findFirst();
      expect(dm!.roomId, ChatViewModel.buildRoomId('me', 'alice'));
      expect(dm.recipientId, 'alice');
      expect(dm.senderId, 'me');
      expect(dm.textContent, 'on my way');
      expect(dm.status, MessageStatus.sending);

      final inGroup = await isar.localMessages
          .filter()
          .messageIdEqualTo('n2')
          .findFirst();
      expect(inGroup!.roomId, 'group_g1');
      expect(inGroup.groupId, 'g1');

      // Another account's reply is dropped, never sent as this one.
      expect(
        await isar.localMessages.filter().messageIdEqualTo('n3').findFirst(),
        isNull,
      );
      expect(socket.sent.map((p) => p['temp_id']), ['n2', 'n1']);
      expect(socket.sent.first['group_id'], 'g1');
      expect(socket.sent.last['recipient_id'], 'alice');
      expect(queue.replies, isEmpty);
    });

    test('a reply already in the chat is not sent again', () async {
      final vm = c.read(chatViewModelProvider.notifier);
      await vm.importNotificationReplies();
      queue.replies.add(
        QueuedReply(
          clientId: 'n1',
          userId: 'me',
          target: 'alice',
          text: 'on my way',
          at: DateTime.utc(2026, 11, 4, 9),
        ),
      );
      socket.sent.clear();
      await vm.importNotificationReplies();
      expect(socket.sent, isEmpty);
      expect(queue.replies, isEmpty);
    });
  }, skip: haveLib ? false : 'Isar native library not found');
}
