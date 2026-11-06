import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/core/platform/sound_board.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/echo.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/services/echo_service.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/echo_providers.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/sound_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/echo_icon.dart';
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Out implements SoundOutput {
  final played = <String>[];
  @override
  Future<void> load(SoundEvent e, SoundChoice c) async {}
  @override
  Future<void> play(SoundEvent e, double v) async => played.add(e.name);
  @override
  Future<void> preview(SoundChoice c, double v) async {}
  @override
  Future<Duration?> probe(String p) async => null;
  @override
  Future<void> dispose() async {}
}

class _Socket extends WebSocketService {
  @override
  bool sendMessage(Map<String, dynamic> payload) => true;
}

class _Profile extends ProfileViewModel {
  @override
  FutureOr<Profile?> build() => Profile(
    userId: 'me',
    displayName: 'Me',
    username: 'me',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _Echos extends EchoService {
  _Echos() : super(Dio());
  @override
  Future<MyEchoStatus> mine() async => const MyEchoStatus();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the defaults: Serafim received, Drop sent, Tick typing', () {
    expect(SoundEvent.received.fallback, const SoundChoice.builtIn('serafim'));
    expect(SoundEvent.sent.fallback, const SoundChoice.builtIn('drop'));
    expect(SoundEvent.typing.fallback, const SoundChoice.builtIn('tick'));
  });

  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  test(
    'the sent sound plays when the server confirms, not on tapping send',
    () async {
      await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      final dir = Directory.systemTemp.createTempSync('sent');
      final isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 's${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        dir.deleteSync(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final out = _Out();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          isarServiceProvider.overrideWithValue(
            IsarService.withDb(Future.value(isar))..accountId = 'me',
          ),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketEventsProvider.overrideWith((ref) => events.stream),
          webSocketServiceProvider.overrideWithValue(_Socket()),
          soundOutputProvider.overrideWithValue(out),
        ],
      );
      addTearDown(c.dispose);
      final vm = c.read(chatViewModelProvider.notifier);
      c.read(soundBoardProvider);
      await Future<void>.delayed(Duration.zero);

      await vm.sendMessage(roomId: 'ann_me', recipientId: 'ann', content: 'hi');
      expect(out.played, isEmpty, reason: 'not yet confirmed');

      final sent = await isar.localMessages.where().findFirst();
      events.add({
        'type': 'message_ack',
        'temp_id': sent!.messageId,
        'message_id': 'srv-1',
        'status': 'sent',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(out.played, ['sent']);
    },
    skip: haveLib ? false : 'Isar native library not found',
  );

  test(
    'the typing sound repeats while they type, and is never cut off midway',
    () async {
      await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      final dir = Directory.systemTemp.createTempSync('typing');
      final isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 't${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        dir.deleteSync(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final out = _Out();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          isarServiceProvider.overrideWithValue(
            IsarService.withDb(Future.value(isar))..accountId = 'me',
          ),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketEventsProvider.overrideWith((ref) => events.stream),
          webSocketServiceProvider.overrideWithValue(_Socket()),
          soundOutputProvider.overrideWithValue(out),
        ],
      );
      addTearDown(c.dispose);
      c.read(chatViewModelProvider.notifier);
      c.read(soundBoardProvider);
      c.read(activeRoomProvider.notifier).set('ann_me');
      await Future<void>.delayed(Duration.zero);

      Future<void> typing(bool state) async {
        events.add({'type': 'typing', 'sender_id': 'ann', 'state': state});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      await typing(true);
      expect(out.played, ['typing'], reason: 'starts at once');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await typing(true);
      expect(out.played, ['typing'], reason: 'a frame must not restart it');

      await Future<void>.delayed(ChatViewModel.typingTickEvery);
      expect(out.played, ['typing', 'typing'], reason: 'it repeats');

      await typing(false);
      await Future<void>.delayed(
        ChatViewModel.typingTickEvery + const Duration(milliseconds: 200),
      );
      expect(out.played, hasLength(2), reason: 'stops when they stop');
    },
    skip: haveLib ? false : 'Isar native library not found',
  );

  testWidgets('Echo sits in the profile menu, with its icon', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentAccountIdProvider.overrideWithValue('me'),
          profileViewModelProvider.overrideWith(_Profile.new),
          myHaloLitProvider.overrideWith((ref) => false),
          echoServiceProvider.overrideWithValue(_Echos()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: Align(
                alignment: Alignment.topRight,
                child: ProfileMenuButton(),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byType(ProfileMenuButton));
    await t.pumpAndSettle();
    expect(find.text('Echo'), findsOneWidget);
    expect(find.byType(EchoIcon), findsOneWidget);
    await t.tap(find.text('Echo'));
    await t.pumpAndSettle();
    expect(find.text('SEND AN ECHO'), findsOneWidget);
  });
}
