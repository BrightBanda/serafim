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
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/services/nickname_service.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/view/nicknames_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/nickname_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/chat/reactions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSocket extends WebSocketService {
  final sent = <Map<String, dynamic>>[];
  @override
  bool sendMessage(Map<String, dynamic> payload) {
    sent.add(payload);
    return true;
  }
}

class _Nicknames extends NicknameService {
  _Nicknames(this.now) : super(Dio());
  Nicknames now;
  final calls = <String>[];

  @override
  Future<Nicknames> get() async => now;

  @override
  Future<Nicknames> set(String userId, String nickname) async {
    calls.add('$userId=$nickname');
    now = Nicknames(
      given: nickname.isEmpty ? {} : {userId: nickname},
      received: now.received,
    );
    return now;
  }
}

void main() {
  group('reactions, as stored', () {
    test('read and written as "user:reaction", junk ignored', () {
      final r = reactionsFrom(['ann:happy', 'bo:cooked', 'cy:nonsense', 'bad']);
      expect(r, {'ann': Reaction.happy, 'bo': Reaction.cooked});
      expect(reactionsTo(r), ['ann:happy', 'bo:cooked']);
      expect(reactionsTo({}), isNull);
      expect(Reaction.values.map((r) => r.name), [
        'okay',
        'happy',
        'celebrate',
        'angry',
        'wow',
        'cooked',
      ]);
    });
  });

  testWidgets('the badge shows each reaction once and how many reacted', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReactionBadge(
            reactions: {
              'a': Reaction.happy,
              'b': Reaction.happy,
              'c': Reaction.cooked,
            },
          ),
        ),
      ),
    );
    expect(find.byType(ReactionDoodle), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the picker offers all six and says which you chose', (t) async {
    Reaction? picked;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReactionPicker(
            current: Reaction.wow,
            onPick: (r) => picked = r,
          ),
        ),
      ),
    );
    expect(find.byType(ReactionDoodle), findsNWidgets(6));
    await t.tap(find.byKey(const ValueKey('react-cooked')));
    expect(picked, Reaction.cooked);
  });

  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  group('reacting', () {
    late Directory dir;
    late Isar isar;
    late FakeSocket socket;
    late ProviderContainer c;

    setUpAll(() async {
      if (haveLib) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      }
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('react');
      isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 'r${DateTime.now().microsecondsSinceEpoch}',
      );
      final service = IsarService.withDb(Future.value(isar))..accountId = 'me';
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      socket = FakeSocket();
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
        ],
      );
      await isar.writeTxn(
        () => isar.localMessages.put(
          LocalMessage()
            ..messageId = 'm1'
            ..roomId = 'ann_me'
            ..senderId = 'ann'
            ..recipientId = 'me'
            ..textContent = 'hi'
            ..status = MessageStatus.read
            ..timestamp = DateTime.utc(2026),
        ),
      );
    });

    tearDown(() async {
      c.dispose();
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    Future<LocalMessage> m1() async =>
        (await isar.localMessages.filter().messageIdEqualTo('m1').findFirst())!;

    test('shows at once, tells the server, and a second tap takes it '
        'away', () async {
      final vm = c.read(chatViewModelProvider.notifier);
      await vm.react(await m1(), Reaction.happy);
      expect((await m1()).reactions, ['me:happy']);
      expect(socket.sent.last, {
        'type': 'react',
        'message_id': 'm1',
        'reaction': 'happy',
      });

      await vm.react(await m1(), Reaction.happy);
      expect((await m1()).reactions, isNull);
      expect(socket.sent.last['reaction'], isNull);
    });

    test('the server\'s word replaces what is shown', () async {
      await IsarService.withDb(
        Future.value(isar),
      ).applyReactions('m1', {'ann': 'cooked', 'me': 'okay'});
      expect(reactionsFrom((await m1()).reactions), {
        'ann': Reaction.cooked,
        'me': Reaction.okay,
      });
    });
  }, skip: haveLib ? false : 'Isar native library not found');

  testWidgets('nicknames: set yours, see theirs', (t) async {
    final server = _Nicknames(
      const Nicknames(received: {'tamara': 'Sunshine'}),
    );
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          nicknameServiceProvider.overrideWithValue(server),
        ],
        child: const MaterialApp(
          home: NicknamesPage(friendId: 'tamara', friendName: 'Tamara'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('"Sunshine"'), findsOneWidget);
    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('nickname-field')),
        matching: find.byType(TextField),
      ),
      'Tam Tam',
    );
    await t.tap(find.byKey(const ValueKey('nickname-save')));
    await t.pumpAndSettle();
    expect(server.calls, ['tamara=Tam Tam']);
    expect(find.textContaining('is now "Tam Tam" to you'), findsOneWidget);
    expect(find.byKey(const ValueKey('nickname-remove')), findsOneWidget);
  });
}
