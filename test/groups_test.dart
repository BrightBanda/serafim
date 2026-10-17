import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/group_service.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/view/group_info_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/member_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

GroupSummary summary(
  String id, {
  GroupRole role = GroupRole.member,
  DateTime? rules,
}) => GroupSummary(
  id: id,
  name: 'Crew',
  myRole: role,
  memberCount: 3,
  joinedAt: DateTime.utc(2026),
  rulesUpdatedAt: rules,
);

GroupMemberInfo member(String id, GroupRole role) => GroupMemberInfo(
  user: PublicUser(id: id, username: id, displayName: id.toUpperCase()),
  role: role,
  joinedAt: DateTime.utc(2026),
);

class FakeGroups extends GroupService {
  FakeGroups() : super(Dio());
  List<GroupSummary> groups = [];
  @override
  Future<List<GroupSummary>> mine() async => groups;
  @override
  Future<List<Map<String, dynamic>>> messagesSince(
    String id, {
    DateTime? after,
  }) async => const [];
}

class FakeSocket extends WebSocketService {
  final sent = <Map<String, dynamic>>[];
  @override
  bool sendMessage(Map<String, dynamic> payload) {
    sent.add(payload);
    return true;
  }
}

void main() {
  group('roles and rules', () {
    test('who may remove whom matches the server', () {
      expect(GroupRole.owner.canRemove(GroupRole.admin), isTrue);
      expect(GroupRole.owner.canRemove(GroupRole.owner), isFalse);
      expect(GroupRole.admin.canRemove(GroupRole.member), isTrue);
      expect(GroupRole.admin.canRemove(GroupRole.admin), isFalse);
      expect(GroupRole.admin.canRemove(GroupRole.owner), isFalse);
      expect(GroupRole.member.canRemove(GroupRole.member), isFalse);
      expect(GroupRole.member.canManage, isFalse);
      expect(GroupRole.admin.canManage, isTrue);
    });

    test('rules show once per version', () {
      final v1 = DateTime.utc(2026, 1, 1);
      final v2 = DateTime.utc(2026, 2, 1);
      expect(shouldShowRules(summary('g'), {}), isFalse); // no rules
      expect(shouldShowRules(summary('g', rules: v1), {}), isTrue);
      expect(shouldShowRules(summary('g', rules: v1), {'g': v1}), isFalse);
      expect(shouldShowRules(summary('g', rules: v2), {'g': v1}), isTrue);
    });

    test('typed UIDs are sent as ids, the rest as usernames', () {
      const uid = '3F2A9C1E-0000-4abc-9def-1234567890ab';
      final parts = const MemberSelection(
        userIds: {'friend-1'},
        typed: ['@sam', uid, 'ada'],
      ).split();
      expect(parts.userIds.toSet(), {'friend-1', uid.toLowerCase()});
      expect(parts.usernames, ['sam', 'ada']);
    });
  });

  testWidgets('member actions follow your role', (tester) async {
    // Tall enough that every member row is built.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> show(GroupRole myRole) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final detail = GroupDetail(
        summary: summary('g', role: myRole),
        members: [
          member('me', myRole),
          member(
            'own',
            myRole == GroupRole.owner ? GroupRole.admin : GroupRole.owner,
          ),
          member('mem', GroupRole.member),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentAccountIdProvider.overrideWithValue('me'),
            groupDetailProvider.overrideWith((ref, id) async => detail),
          ],
          child: const MaterialApp(home: GroupInfoPage(groupId: 'g')),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(GroupRole.member);
    expect(find.byTooltip('Member options'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('This group has no rules.'), findsOneWidget);

    await show(GroupRole.admin);
    // An admin can remove the plain member, but not the owner.
    expect(find.byTooltip('Member options'), findsOneWidget);
    await tester.tap(find.byTooltip('Member options'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from group'), findsOneWidget);
    expect(find.text('Make admin'), findsNothing);
    expect(find.text('Make owner'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await show(GroupRole.owner);
    expect(find.byTooltip('Member options'), findsNWidgets(2));
    expect(find.text('Edit'), findsOneWidget);
  });

  // ------------------------------------------------- local database ---
  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  group('group messages on the device', () {
    late Directory dir;
    late Isar isar;
    late IsarService service;
    late ProviderContainer c;
    late StreamController<Map<String, dynamic>> socketIn;
    late FakeSocket socket;
    late FakeGroups groups;

    setUpAll(() async {
      if (haveLib) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      }
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('groups');
      isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 'g${DateTime.now().microsecondsSinceEpoch}',
      );
      service = IsarService.withDb(Future.value(isar))..accountId = 'me';
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      socketIn = StreamController<Map<String, dynamic>>();
      socket = FakeSocket();
      groups = FakeGroups()..groups = [summary('g1')];
      c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localCacheProvider.overrideWithValue(LocalCache(prefs)),
          isarServiceProvider.overrideWithValue(service),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketStreamProvider.overrideWith((ref) => socketIn.stream),
          webSocketServiceProvider.overrideWithValue(socket),
          groupServiceProvider.overrideWithValue(groups),
        ],
      );
      // Kept listened, as the main screen does in the app (Riverpod pauses
      // providers nobody listens to).
      c.listen(chatViewModelProvider, (_, _) {});
    });

    tearDown(() async {
      c.dispose();
      await socketIn.close();
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    /// Waits (up to 5 s) for the socket event to be processed, rather than a
    /// fixed delay that a busy machine can outrun.
    Future<void> until(Future<bool> Function() done) async {
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!await done() && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    Future<bool> stored(String id) async =>
        await service.getMessageById(id) != null;

    test(
      'a live group message lands in the group room, unread, and is not a "stranger"',
      () async {
        socketIn.add({
          'type': 'message',
          'message_id': 'm1',
          'group_id': 'g1',
          'sender_id': 'bob',
          'content': 'hi all',
          'kind': 'text',
          'timestamp': '2026-10-01T10:00:00Z',
        });
        await until(() => stored('m1'));
        final m = (await service.getMessageById('m1'))!;
        expect(m.roomId, 'group_g1');
        expect(m.groupId, 'g1');

        final room = (await isar.localChatRooms.getByRoomId('group_g1'))!;
        expect(room.unreadCount, 1);
        expect(room.lastMessageText, 'hi all');
        expect(await service.watchConversationPeerIds('me').first, isEmpty);

        await service.markRoomRead('group_g1', 'me');
        expect(
          (await isar.localChatRooms.getByRoomId('group_g1'))!.unreadCount,
          0,
        );
        expect(await service.getPendingReadAcks('me'), isEmpty);
      },
    );

    test('being removed wipes the group from the device', () async {
      socketIn.add({
        'type': 'message',
        'message_id': 'm1',
        'group_id': 'g1',
        'sender_id': 'bob',
        'content': 'x',
        'timestamp': '2026-10-01T10:00:00Z',
      });
      await until(() => stored('m1'));
      expect(await stored('m1'), isTrue);
      groups.groups = [];
      socketIn.add({'type': 'group_removed', 'group_id': 'g1'});
      await until(() async => !await stored('m1'));
      expect(await service.getMessageById('m1'), isNull);
      expect(await isar.localChatRooms.getByRoomId('group_g1'), isNull);
    });

    test('messages to a group go to the group, not a person', () async {
      await c
          .read(chatViewModelProvider.notifier)
          .sendMessage(
            roomId: 'group_g1',
            recipientId: 'g1',
            groupId: 'g1',
            content: 'hey',
          );
      expect(socket.sent.single['group_id'], 'g1');
      expect(socket.sent.single.containsKey('recipient_id'), isFalse);
    });
  }, skip: haveLib ? false : 'Isar native library not found');
}
