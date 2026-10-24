import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/chat_filter.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_list_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = 'me';

PublicUser person(String id, String name) =>
    PublicUser(id: id, username: id, displayName: name);

GroupSummary aGroup(String id, String name) => GroupSummary(
  id: id,
  name: name,
  myRole: GroupRole.member,
  memberCount: 2,
  joinedAt: DateTime.utc(2026),
);

RoomPreview preview({int unread = 0}) => RoomPreview(
  text: 'hi',
  timestamp: DateTime.utc(2026),
  senderId: 'other',
  isImage: false,
  isDeleted: false,
  unread: unread,
);

void main() {
  group('applyChatFilter', () {
    final friend = person('f1', 'A Friend');
    final stranger = person('s1', 'A Stranger');
    final group = aGroup('g1', 'A Group');
    final entries = <ChatEntry>[
      ChatEntry(friend.id, friend),
      ChatEntry(stranger.id, null),
      ChatEntry(group.id, null, group),
    ];
    final friendRoom = ChatViewModel.buildRoomId(me, friend.id);
    final groupRoom = group.roomId;
    final previews = {
      friendRoom: preview(unread: 3),
      groupRoom: preview(unread: 0),
    };

    test('all keeps everything', () {
      expect(applyChatFilter(entries, ChatFilter.all, previews, me).length, 3);
    });

    test('friends keeps only the people you are friends with', () {
      final kept = applyChatFilter(entries, ChatFilter.friends, previews, me);
      expect(kept.map((e) => e.id), ['f1']);
    });

    test('groups keeps only the group chats', () {
      final kept = applyChatFilter(entries, ChatFilter.groups, previews, me);
      expect(kept.map((e) => e.id), ['g1']);
    });

    test('unread keeps only the chats with something unread', () {
      final kept = applyChatFilter(entries, ChatFilter.unread, previews, me);
      expect(kept.map((e) => e.id), ['f1']);
    });

    test('a custom filter keeps the rooms it names', () {
      final filter = ChatFilter(
        id: 'c1',
        name: 'Work',
        kind: ChatFilterKind.custom,
        roomIds: {groupRoom},
      );
      final kept = applyChatFilter(entries, filter, previews, me);
      expect(kept.map((e) => e.id), ['g1']);
    });
  });

  test('the unread count is the number of chats with something unread', () {
    final entries = <ChatEntry>[
      ChatEntry('f1', person('f1', 'A')),
      ChatEntry('s1', null),
    ];
    final previews = {ChatViewModel.buildRoomId(me, 'f1'): preview(unread: 2)};
    expect(countUnread(entries, previews, me), 1);
  });

  group('persistence', () {
    test('a custom filter survives a round trip', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = LocalCache(prefs);

      const filter = ChatFilter(
        id: 'custom_1',
        name: 'Work',
        kind: ChatFilterKind.custom,
        roomIds: {'room_a', 'room_b'},
      );
      await cache.saveChatFilters(me, [filter]);

      final saved = cache.chatFilters(me);
      expect(saved, isNotNull);
      expect(saved!.length, 1);
      expect(saved.first.name, 'Work');
      expect(saved.first.kind, ChatFilterKind.custom);
      expect(saved.first.roomIds, {'room_a', 'room_b'});
    });

    test('nothing saved means no filters', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = LocalCache(prefs);
      expect(cache.chatFilters(me), isNull);
    });
  });

  testWidgets('tapping Unread hides the chats with nothing unread', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs);

    final friend = person('f1', 'Readable Friend');
    final noisy = person('s1', 'Noisy Stranger');
    // The stranger's name comes from the copy saved on the phone.
    await cache.savePerson(me, noisy);

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutoRetry,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localCacheProvider.overrideWithValue(cache),
          currentUserProvider.overrideWithValue(
            AppUser(id: me, isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue(me),
          friendsProvider.overrideWith((ref) => [friend]),
          publicUserProvider.overrideWith(
            (ref, id) => Completer<PublicUser>().future,
          ),
          conversationPeerIdsProvider.overrideWith(() => _FixedPeers(['s1'])),
          chatRoomsProvider.overrideWith(_NoRooms.new),
          roomMessagesStreamProvider.overrideWith(
            (ref, roomId) => Stream.value(<LocalMessage>[]),
          ),
          roomPreviewsProvider.overrideWithValue({
            ChatViewModel.buildRoomId(me, noisy.id): preview(unread: 2),
          }),
          chatViewModelProvider.overrideWith(_FakeChat.new),
        ],
        child: const MaterialApp(home: ChatListPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Both chats are on the list to start with.
    expect(find.text('Readable Friend'), findsOneWidget);
    expect(find.text('Noisy Stranger'), findsOneWidget);

    await tester.tap(find.text('Unread 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Only the one with something unread is left.
    expect(find.text('Noisy Stranger'), findsOneWidget);
    expect(find.text('Readable Friend'), findsNothing);
  });

  testWidgets('holding a chat offers clear, view profile and remove', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cleared = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutoRetry,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWithValue(
            AppUser(id: me, isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue(me),
          friendsProvider.overrideWith(
            (ref) => [person('f1', 'Ann'), person('f2', 'Bo')],
          ),
          conversationPeerIdsProvider.overrideWith(() => _FixedPeers([])),
          chatRoomsProvider.overrideWith(_NoRooms.new),
          roomPreviewsProvider.overrideWithValue({}),
          chatViewModelProvider.overrideWith(_FakeChat.new),
          chatListActionsProvider.overrideWith(
            (ref) => _RecordingActions(ref, cleared),
          ),
        ],
        child: const MaterialApp(home: ChatListPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    Future<void> choose(String name, String option, String confirm) async {
      await tester.longPress(find.text(name));
      await tester.pumpAndSettle();
      expect(find.text('Clear chat'), findsOneWidget);
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Remove chat'), findsOneWidget);
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
      await tester.tap(find.text(confirm));
      await tester.pumpAndSettle();
    }

    // Clearing keeps the chat on the list.
    await choose('Bo', 'Clear chat', 'Clear');
    expect(cleared, [ChatViewModel.buildRoomId(me, 'f2')]);
    expect(find.text('Bo'), findsOneWidget);

    // Removing clears it and takes it off, and that is remembered.
    await choose('Ann', 'Remove chat', 'Remove');
    final annRoom = ChatViewModel.buildRoomId(me, 'f1');
    expect(cleared.last, annRoom);
    expect(find.text('Ann'), findsNothing);
    expect(find.text('Bo'), findsOneWidget);
    expect(LocalCache(prefs).removedChats(me).keys, [annRoom]);
  });
}

/// Records what was cleared instead of touching a database.
class _RecordingActions extends ChatListActions {
  _RecordingActions(super.ref, this.cleared);

  final List<String> cleared;

  @override
  Future<void> clear(String roomId) async => cleared.add(roomId);
}

class _FakeChat extends ChatViewModel {
  @override
  ChatState build() => const ChatState();
  @override
  Future<void> markRoomRead(String roomId) async {}
}

class _NoRooms extends ChatRoomsNotifier {
  @override
  List<LocalChatRoom> build() => const [];
}

class _FixedPeers extends ConversationPeersNotifier {
  _FixedPeers(this._ids);

  final List<String> _ids;

  @override
  List<String> build() => _ids;
}
