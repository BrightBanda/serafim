import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_search_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';

const me = 'me';

PublicUser person(String id, String name, String username) =>
    PublicUser(id: id, username: username, displayName: name);

LocalMessage msg(
  String id,
  String text, {
  String from = 'sam',
  String to = me,
  int minute = 0,
  bool deleted = false,
  bool hidden = false,
}) => LocalMessage()
  ..messageId = id
  ..roomId = 'room_$from$to'
  ..senderId = from
  ..recipientId = to
  ..textContent = text
  ..isDeleted = deleted
  ..isHiddenForMe = hidden
  ..status = MessageStatus.sent
  ..timestamp = DateTime.utc(2026, 1, 1, 10, minute);

void main() {
  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  late Directory dir;
  late Isar isar;
  late IsarService service;

  setUpAll(() async {
    if (haveLib)
      await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
  });

  setUp(() async {
    if (!haveLib) markTestSkipped('libisar.so not found in the pub cache');
    dir = await Directory.systemTemp.createTemp('isar_search');
    isar = await Isar.open(
      [LocalMessageSchema, LocalChatRoomSchema],
      directory: dir.path,
      name: 'search_${DateTime.now().microsecondsSinceEpoch}',
    );
    service = IsarService.withDb(Future.value(isar));
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  group('searching message text', () {
    test('finds matches in any case, newest first', () async {
      await service.saveMessage(msg('a', 'Lunch at noon?', minute: 1));
      await service.saveMessage(
        msg('b', 'bring LUNCH money', minute: 5, from: me, to: 'sam'),
      );
      await service.saveMessage(msg('c', 'unrelated', minute: 9));

      final hits = await service.searchMessages('lunch', me);
      expect(hits.map((m) => m.messageId), ['b', 'a']);
    });

    test(
      'never returns deleted, hidden, or other people\'s conversations',
      () async {
        await service.saveMessage(msg('ok', 'secret plan'));
        await service.saveMessage(msg('del', 'secret deleted', deleted: true));
        await service.saveMessage(msg('hid', 'secret hidden', hidden: true));
        await service.saveMessage(
          msg('other', 'secret elsewhere', from: 'x', to: 'y'),
        );

        final hits = await service.searchMessages('secret', me);
        expect(hits.map((m) => m.messageId), ['ok']);
      },
    );

    test(
      'empty or blank queries find nothing, and the limit is respected',
      () async {
        for (var i = 0; i < 6; i++) {
          await service.saveMessage(msg('m$i', 'hello $i', minute: i));
        }
        expect(await service.searchMessages('', me), isEmpty);
        expect(await service.searchMessages('   ', me), isEmpty);
        expect(
          await service.searchMessages('hello', me, limit: 3),
          hasLength(3),
        );
      },
    );
  });

  group('the search provider', () {
    ProviderContainer container({
      List<PublicUser> friends = const [],
      List<String> peers = const [],
      Map<String, PublicUser> strangers = const {},
    }) {
      final c = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue(me),
          isarServiceProvider.overrideWithValue(service),
          friendsProvider.overrideWith((ref) => friends),
          conversationPeerIdsProvider.overrideWith(
            (ref) => Stream.value(peers),
          ),
          publicUserProvider.overrideWith((ref, id) async {
            final u = strangers[id];
            if (u == null) throw StateError('no such user');
            return u;
          }),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('finds people by display name and username, ignoring case', () async {
      final c = container(
        friends: [
          person('sam', 'Sam Ndlovu', 'sam_n'),
          person('al', 'Alex', 'alexander'),
        ],
        peers: ['sam', 'al'],
      );
      final byName = await c.read(chatSearchProvider('ndlo').future);
      expect(byName.people.map((p) => p.id), ['sam']);
      final byUser = await c.read(chatSearchProvider('ALEXAND').future);
      expect(byUser.people.map((p) => p.id), ['al']);
      expect((await c.read(chatSearchProvider('zzz').future)).isEmpty, isTrue);
    });

    test(
      'finds messages and attaches the right person, mine or theirs',
      () async {
        await service.saveMessage(msg('1', 'pizza tonight?', from: 'sam'));
        await service.saveMessage(
          msg('2', 'yes pizza!', from: me, to: 'sam', minute: 2),
        );
        final c = container(
          friends: [person('sam', 'Sam', 'sam')],
          peers: ['sam'],
        );

        final found = await c.read(chatSearchProvider('pizza').future);
        expect(found.messages.map((h) => h.message.messageId), ['2', '1']);
        expect(found.messages.every((h) => h.person.id == 'sam'), isTrue);
      },
    );

    test('includes people you messaged but are not friends with', () async {
      await service.saveMessage(msg('1', 'hello stranger', from: 'nina'));
      final c = container(
        peers: ['nina'],
        strangers: {'nina': person('nina', 'Nina Bell', 'nina_b')},
      );
      final byName = await c.read(chatSearchProvider('bell').future);
      expect(byName.people.map((p) => p.id), ['nina']);
      final byText = await c.read(chatSearchProvider('stranger').future);
      expect(byText.messages.single.person.id, 'nina');
    });

    test(
      'a stranger whose profile cannot load does not break the search',
      () async {
        await service.saveMessage(msg('1', 'hello', from: 'ghost'));
        final c = container(peers: ['ghost']);
        final found = await c.read(chatSearchProvider('hello').future);
        expect(found.messages, isEmpty); // nobody to attach it to, but no crash
      },
    );
  });

  group('highlighting', () {
    const base = TextStyle(fontSize: 10);
    const hit = TextStyle(fontSize: 10, fontWeight: FontWeight.bold);

    List<String> parts(TextSpan s, {required bool matched}) => [
      for (final c in s.children!.cast<TextSpan>())
        if ((c.style == hit) == matched) c.text!,
    ];

    test('marks every occurrence, keeping the original casing', () {
      final span = highlightMatch('Pizza or pizza? PIZZA!', 'pizza', base, hit);
      expect(parts(span, matched: true), ['Pizza', 'pizza', 'PIZZA']);
      expect(parts(span, matched: false), [' or ', '? ', '!']);
    });

    test('no match, empty query, and edges behave', () {
      expect(highlightMatch('hello', 'zzz', base, hit).children!.length, 1);
      expect(highlightMatch('hello', '', base, hit).text, 'hello');
      final edge = highlightMatch('abc', 'abc', base, hit);
      expect(parts(edge, matched: true), ['abc']);
    });
  });

  group('the chat list screen', () {
    final sam = person('sam', 'Sam Ndlovu', 'sam_n');
    final alex = person('al', 'Alex Moyo', 'alexm');

    Future<void> pumpList(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              AppUser(id: me, isActive: true, createdAt: DateTime.utc(2026)),
            ),
            currentAccountIdProvider.overrideWithValue(me),
            friendsProvider.overrideWith((ref) => [sam, alex]),
            conversationPeerIdsProvider.overrideWith(
              (ref) => Stream.value(['sam', 'al']),
            ),
            roomSummaryProvider.overrideWith(
              (ref, key) => Stream.value(const RoomSummary()),
            ),
            chatSearchProvider.overrideWith((ref, query) async {
              final q = query.toLowerCase();
              return ChatSearchResults(
                people: [sam, alex]
                    .where((p) => p.displayName.toLowerCase().contains(q))
                    .toList(),
                messages: q == 'pizza'
                    ? [
                        MessageHit(
                          message: msg('1', 'pizza tonight?'),
                          person: sam,
                        ),
                      ]
                    : const [],
              );
            }),
          ],
          child: const MaterialApp(home: ChatListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the search button opens a search field, and closes it again', (
      tester,
    ) async {
      await pumpList(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Sam Ndlovu'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search chats and messages'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Sam Ndlovu'), findsOneWidget);
    });

    testWidgets('typing filters chats and shows matching messages', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alex');
      await tester.pump(const Duration(milliseconds: 400)); // past the debounce
      await tester.pumpAndSettle();
      expect(find.text('CHATS'), findsOneWidget);
      expect(find.text('Alex Moyo'), findsOneWidget);
      expect(find.text('Sam Ndlovu'), findsNothing);
      expect(find.text('MESSAGES'), findsNothing);

      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('MESSAGES'), findsOneWidget);
      expect(find.byType(RichText), findsWidgets);
      expect(find.textContaining('pizza', findRichText: true), findsWidgets);
    });

    testWidgets('no matches says so, and offers Discover', (tester) async {
      await pumpList(tester);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'qwerty');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No chats or messages match "qwerty"'),
        findsOneWidget,
      );
      expect(
        find.text('Looking for someone new? Search Discover'),
        findsOneWidget,
      );
    });

    testWidgets('the clear button empties the query and keeps searching open', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'alex');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Sam Ndlovu'), findsNothing);

      // Two x icons now: the field's "clear" and the app bar's "close search".
      // The Scaffold builds its body before its app bar, so the field's comes
      // first in the widget tree.
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('ALL CHATS'), findsOneWidget); // back to the full list
      expect(find.text('Sam Ndlovu'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // still searching
    });
  });
}
