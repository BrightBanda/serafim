import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';

const me = 'me';
const peer = 'peer';
const room = 'me_peer';

LocalMessage msg(
  String id, {
  String sender = peer,
  String recipient = me,
  String text = 'hi',
  MessageStatus status = MessageStatus.sent,
  int minute = 0,
}) => LocalMessage()
  ..messageId = id
  ..roomId = room
  ..senderId = sender
  ..recipientId = recipient
  ..textContent = text
  ..status = status
  ..timestamp = DateTime.utc(2026, 1, 1, 10, minute);

void main() {
  late Directory dir;
  late Isar isar;
  late IsarService service;

  // Isar's native library ships inside the flutter_libs package; tests load
  // it from the pub cache (Linux).
  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  setUpAll(() async {
    if (haveLib) {
      await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
    }
  });

  setUp(() async {
    if (!haveLib) markTestSkipped('libisar.so not found in the pub cache');
    dir = await Directory.systemTemp.createTemp('isar_test');
    isar = await Isar.open(
      [LocalMessageSchema, LocalChatRoomSchema],
      directory: dir.path,
      name: 'test_${DateTime.now().microsecondsSinceEpoch}',
    );
    service = IsarService.withDb(Future.value(isar))..accountId = me;
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('applyEdit changes text and marks the message edited', () async {
    await service.saveMessage(msg('a', sender: me, recipient: peer));
    final at = DateTime.utc(2026, 1, 1, 11);
    await service.applyEdit('a', 'fixed', at);

    final m = (await service.getMessageById('a'))!;
    expect(m.textContent, 'fixed');
    expect(m.editedAt!.toUtc(), at);
    expect(
      m.timestamp.toUtc(),
      DateTime.utc(2026, 1, 1, 10),
    ); // ordering untouched
  });

  test(
    'applyDelete wipes content and the image file but keeps the row',
    () async {
      final file = File('${dir.path}/pic.jpg')..writeAsBytesSync([1, 2, 3]);
      await service.saveMessage(
        msg('img', sender: me, recipient: peer)
          ..type = MessageType.image
          ..localMediaPath = file.path,
      );

      await service.applyDelete('img');

      final m = (await service.getMessageById('img'))!;
      expect(m.isDeleted, isTrue);
      expect(m.textContent, isNull);
      expect(m.localMediaPath, isNull);
      expect(m.timestamp.toUtc(), DateTime.utc(2026, 1, 1, 10));
      expect(file.existsSync(), isFalse);
    },
  );

  test('an edit that arrives after a delete is ignored', () async {
    await service.saveMessage(msg('a', sender: me, recipient: peer));
    await service.applyDelete('a');
    await service.applyEdit('a', 'zombie', DateTime.utc(2026, 1, 2));
    expect((await service.getMessageById('a'))!.textContent, isNull);
  });

  test('edit/delete of an unknown message is a harmless no-op', () async {
    await service.applyEdit('nope', 'x', DateTime.utc(2026));
    await service.applyDelete('nope');
  });

  test(
    'status never moves backwards (a late delivered cannot undo read)',
    () async {
      await service.saveMessage(
        msg('a', sender: me, recipient: peer, status: MessageStatus.read),
      );
      await service.updateMessageStatus('a', MessageStatus.delivered);
      expect((await service.getMessageById('a'))!.status, MessageStatus.read);

      await service.updateMessageStatus('a', MessageStatus.failed);
      expect((await service.getMessageById('a'))!.status, MessageStatus.failed);
    },
  );

  test('markRoomRead only touches incoming unread messages', () async {
    await service.saveMessage(msg('in1'));
    await service.saveMessage(msg('in2', status: MessageStatus.read));
    await service.saveMessage(msg('out', sender: me, recipient: peer));

    final ids = await service.markRoomRead(room, me);

    expect(ids, ['in1']);
    expect((await service.getMessageById('in1'))!.readAckPending, isTrue);
    expect((await service.getMessageById('in2'))!.readAckPending, isFalse);
    expect((await service.getMessageById('out'))!.status, MessageStatus.sent);
    expect((await service.getPendingReadAcks(me)).map((m) => m.messageId), [
      'in1',
    ]);

    await service.clearReadAckPending(['in1']);
    expect(await service.getPendingReadAcks(me), isEmpty);
  });

  test('room summary reports the latest message and unread count', () async {
    await service.saveMessage(msg('old', minute: 1));
    await service.saveMessage(msg('new', minute: 5, text: 'latest'));
    await service.saveMessage(
      msg('mine', sender: me, recipient: peer, minute: 3),
    );

    final row = (await service.watchAllChatRooms().first).single;

    expect(row.roomId, room);
    expect(row.lastMessageText, 'latest');
    expect(row.lastMessageTimestamp.toUtc(), DateTime.utc(2026, 1, 1, 10, 5));
    expect(row.peerUserId, peer);
    expect(row.unreadCount, 2);
  });

  test('conversation peers include non-friends, once each', () async {
    await service.saveMessage(msg('a')); // peer -> me
    await service.saveMessage(msg('b', sender: me, recipient: peer));
    final other = msg('c', sender: 'other', recipient: me)..roomId = 'me_other';
    await service.saveMessage(other);

    final peers = await service.watchConversationPeerIds(me).first;
    expect(peers.toSet(), {peer, 'other'});
    expect(peers.length, 2);
  });

  test('sync ids cover both directions, newest first, capped', () async {
    await service.saveMessage(msg('in', minute: 1));
    await service.saveMessage(
      msg('out', sender: me, recipient: peer, minute: 2),
    );
    await service.saveMessage(msg('x', sender: 'a', recipient: 'b', minute: 3));

    expect(await service.getRecentSyncIds(me), ['out', 'in']);
    expect(await service.getRecentSyncIds(me, limit: 1), ['out']);
  });

  test('deleteLocalMessage removes an unsent message and its file', () async {
    final file = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
    await service.saveMessage(
      msg('tmp', sender: me, recipient: peer, status: MessageStatus.failed)
        ..localMediaPath = file.path,
    );
    await service.deleteLocalMessage('tmp');
    expect(await service.getMessageById('tmp'), isNull);
    expect(file.existsSync(), isFalse);
  });

  test(
    'delete for me hides the message and wipes its image, keeping the row',
    () async {
      final file = File('${dir.path}/in.jpg')..writeAsBytesSync([1, 2]);
      await service.saveMessage(
        msg('img')
          ..type = MessageType.image
          ..localMediaPath = file.path,
      );
      await service.saveMessage(msg('keep', minute: 1));

      await service.hideMessageForMe('img');

      final hidden = (await service.getMessageById('img'))!;
      expect(hidden.isHiddenForMe, isTrue);
      expect(hidden.localMediaPath, isNull);
      expect(file.existsSync(), isFalse);

      // Gone from the conversation, the preview and the unread count...
      final visible = await service.watchMessagesForRoom(room).first;
      expect(visible.map((m) => m.messageId), ['keep']);
      final row = (await service.watchAllChatRooms().first).single;
      expect(row.unreadCount, 1);
      // ...and a re-push from the server (same id) cannot undelete it.
      expect((await service.getMessageById('img'))!.isHiddenForMe, isTrue);
    },
  );

  test(
    'retention removes only messages older than the cutoff, with their files',
    () async {
      final file = File('${dir.path}/old.jpg')..writeAsBytesSync([1]);
      await service.saveMessage(
        (msg('old')..timestamp = DateTime.utc(2025, 1, 1))
          ..type = MessageType.image
          ..localMediaPath = file.path,
      );
      await service.saveMessage(
        msg('recent')..timestamp = DateTime.utc(2026, 6, 1),
      );

      final removed = await service.purgeOlderThan(DateTime.utc(2026, 1, 1));

      expect(removed, 1);
      expect(await service.getMessageById('old'), isNull);
      expect(await service.getMessageById('recent'), isNotNull);
      expect(file.existsSync(), isFalse);
    },
  );

  test('reply references survive the round trip', () async {
    await service.saveMessage(msg('orig'));
    await service.saveMessage(
      msg('reply', sender: me, recipient: peer)..replyToId = 'orig',
    );
    expect((await service.getMessageById('reply'))!.replyToId, 'orig');
  });

  group('summary rows and windows', () {
    test('mark read, edit and delete keep the row current', () async {
      await service.saveMessage(msg('a', minute: 1, text: 'hello'));
      await service.saveMessage(msg('b', minute: 2, text: 'second'));
      var row = (await service.watchAllChatRooms().first).single;
      expect(row.unreadCount, 2);

      await service.applyEdit('b', 'edited', DateTime.utc(2026, 1, 2));
      row = (await service.watchAllChatRooms().first).single;
      expect(row.lastMessageText, 'edited');

      await service.applyDelete('b');
      row = (await service.watchAllChatRooms().first).single;
      expect(row.lastMessageDeleted, isTrue);
      expect(row.lastMessageText, isNull);

      await service.markRoomRead(room, me);
      row = (await service.watchAllChatRooms().first).single;
      expect(row.unreadCount, 0);
    });

    test('hiding the only message removes the row', () async {
      await service.saveMessage(msg('a'));
      await service.hideMessageForMe('a');
      expect(await service.watchAllChatRooms().first, isEmpty);
    });

    test('rebuildRooms backfills rows from existing messages', () async {
      await service.saveMessage(msg('a', minute: 1));
      await isar.writeTxn(() => isar.localChatRooms.clear());
      expect(await service.watchAllChatRooms().first, isEmpty);

      await service.rebuildRooms();
      final row = (await service.watchAllChatRooms().first).single;
      expect(row.roomId, room);
      expect(row.unreadCount, 1);
    });

    test('another account sees no row for these messages', () async {
      await service.saveMessage(msg('a'));
      service.accountId = 'someone-else';
      await service.rebuildRooms();
      expect(await service.watchAllChatRooms().first, isEmpty);
    });

    test('the window returns only the newest messages, newest first', () async {
      for (var i = 0; i < 10; i++) {
        await service.saveMessage(msg('m$i', minute: i));
      }
      final page = await service.watchMessagesForRoom(room, limit: 3).first;
      expect(page.map((m) => m.messageId), ['m9', 'm8', 'm7']);

      final older = await service.getMessagesByIds(['m1', 'nope']);
      expect(older.keys, ['m1']);
      expect(
        await service.countMessagesAtOrAfter(room, DateTime.utc(2026, 1, 1, 10, 7)),
        3,
      );
    });
  });
}
