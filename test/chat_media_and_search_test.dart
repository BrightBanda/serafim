import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/presentation/view/chat_media_page.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';

LocalMessage msg(
  String id,
  MessageType type, {
  String? text,
  String? path,
  String? fileName,
  int minute = 0,
  String room = 'me_bob',
  bool deleted = false,
}) => LocalMessage()
  ..messageId = id
  ..roomId = room
  ..senderId = 'bob'
  ..recipientId = 'me'
  ..type = type
  ..textContent = text
  ..localMediaPath = path
  ..fileName = fileName
  ..isDeleted = deleted
  ..status = MessageStatus.sent
  ..timestamp = DateTime.utc(2026, 1, 1, 12, minute);

void main() {
  group('sorting a chat into media', () {
    test('each kind lands in its own tab; links are found in text', () {
      final entries = chatMediaEntries([
        msg('p', MessageType.image, path: '/x/p.jpg'),
        msg('v', MessageType.video),
        msg('vn', MessageType.audio),
        msg('a', MessageType.audioFile, fileName: 'song.mp3'),
        msg(
          'l',
          MessageType.text,
          text: 'see https://example.com and www.serafim.app',
        ),
        msg('t', MessageType.text, text: 'just words'),
        msg('s', MessageType.sticker, text: 'doodles/frog'),
      ]);
      expect(
        [for (final e in entries) '${e.message.messageId}:${e.kind.name}'],
        ['p:image', 'v:video', 'vn:audio', 'a:audio', 'l:link', 'l:link'],
      );
      expect(entries[4].link.toString(), 'https://example.com');
      expect(entries[5].link!.host, 'www.serafim.app');
    });

    test('deleted messages and photos no longer on the phone are left out', () {
      final entries = chatMediaEntries([
        msg('gone', MessageType.video, deleted: true),
        msg('nofile', MessageType.image),
      ]);
      expect(entries, isEmpty);
    });
  });

  testWidgets('the chat menu offers search and media', (tester) async {
    var searched = 0, media = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMenuButton(
            roomId: 'r',
            onSearch: () => searched++,
            onMedia: () => media++,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Media & links'), findsOneWidget);
    expect(find.text('Chat background'), findsOneWidget);

    await tester.tap(find.text('Media & links'));
    await tester.pumpAndSettle();
    expect(media, 1);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(searched, 1);
  });

  testWidgets('without the callbacks, only the background is offered', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChatMenuButton(roomId: 'r')),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsNothing);
    expect(find.text('Media & links'), findsNothing);
  });

  // ------------------------------------------------------------ the store ---
  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  group('finding things in one chat', () {
    late Directory dir;
    late Isar isar;
    late IsarService service;

    setUpAll(() async {
      if (haveLib) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      }
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('chat_search');
      isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 's${DateTime.now().microsecondsSinceEpoch}',
      );
      service = IsarService.withDb(Future.value(isar))..accountId = 'me';
      await isar.writeTxn(
        () => isar.localMessages.putAll([
          msg('m1', MessageType.text, text: 'Dinner at seven?', minute: 1),
          msg('m2', MessageType.text, text: 'dinner was great', minute: 2),
          msg(
            'm3',
            MessageType.audioFile,
            fileName: 'Dinner song.mp3',
            minute: 3,
          ),
          msg('m4', MessageType.sticker, text: 'doodles/dinner', minute: 4),
          msg(
            'm5',
            MessageType.text,
            text: 'dinner?',
            minute: 5,
            deleted: true,
          ),
          msg('m6', MessageType.text, text: 'dinner', minute: 6, room: 'other'),
          msg(
            'm7',
            MessageType.image,
            text: 'dinner pic',
            path: '/p.jpg',
            minute: 7,
          ),
          msg('m8', MessageType.text, text: 'link: https://x.com', minute: 8),
        ]),
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    test(
      'search matches words and file names in this chat, newest first',
      () async {
        final found = await service.searchRoom('me_bob', 'DINNER');
        // Not the sticker (its text is an id), the deleted one, or the other
        // chat.
        expect(found.map((m) => m.messageId), ['m7', 'm3', 'm2', 'm1']);
        expect(await service.searchRoom('me_bob', '   '), isEmpty);
      },
    );

    test('media covers pictures, files and messages with links', () async {
      final all = await service.watchRoomMedia('me_bob').first;
      expect(all.map((m) => m.messageId), ['m8', 'm7', 'm3']);
    });
  }, skip: haveLib ? false : 'Isar native library not found');
}
