import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/services/scheduled_message_service.dart';
import 'package:serafim/src/presentation/view/widgets/scheduled_message_sheets.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/scheduled_message_providers.dart';
import 'package:serafim/src/utils/chat/attachment_sheet.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/image_picking.dart';

class _Server extends ScheduledMessageService {
  _Server() : super(Dio());

  final rows = <ScheduledMessage>[];
  final removed = <String>[];
  String? refuse;
  var _next = 0;

  @override
  Future<List<ScheduledMessage>> list() async => List.of(rows);

  @override
  Future<ScheduledMessage> create({
    String? recipientId,
    String? groupId,
    required String content,
    required DateTime sendAt,
  }) async {
    if (refuse != null) throw ApiException(refuse!);
    final m = ScheduledMessage(
      id: 's${_next++}',
      recipientId: recipientId,
      groupId: groupId,
      content: content,
      sendAt: sendAt.toUtc(),
    );
    rows.add(m);
    return m;
  }

  @override
  Future<ScheduledMessage> update(
    String id, {
    required String content,
    required DateTime sendAt,
  }) async {
    final m = ScheduledMessage(
      id: id,
      recipientId: 'ann',
      content: content,
      sendAt: sendAt.toUtc(),
    );
    rows[rows.indexWhere((r) => r.id == id)] = m;
    return m;
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    rows.removeWhere((r) => r.id == id);
  }
}

const room = 'ann_me';

void main() {
  group('the attachment sheet', () {
    testWidgets('shows every option, and returns the one tapped', (t) async {
      Object? chosen;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => chosen = await showAttachmentSheet(
                  context,
                  options: const [
                    AttachOption(
                      value: 'gallery',
                      icon: Icons.perm_media_outlined,
                      label: 'Gallery',
                      color: Colors.blue,
                    ),
                    AttachOption(
                      value: 'scribble',
                      icon: Icons.draw_outlined,
                      label: 'Scribble',
                      color: Colors.teal,
                      disabledReason: 'Not here.',
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Scribble'), findsOneWidget);
      // A held-back option can still be tapped, so the chat can say why.
      await t.tap(find.byKey(const ValueKey('attach-scribble')));
      await t.pumpAndSettle();
      expect(chosen, 'scribble');
      expect(find.text('Gallery'), findsNothing);
    });

    testWidgets('the bar has one paperclip and no separate pencil', (t) async {
      var attaches = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatInputBar(onAttach: () => attaches++)),
        ),
      );
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byIcon(Icons.draw_outlined), findsNothing);
      await t.tap(find.byKey(const ValueKey('attach-button')));
      expect(attaches, 1);
    });

    test('Gallery uses the Photo Picker, not the file browser', () {
      final android = ImagePickerAndroid();
      expect(android.useAndroidPhotoPicker, isFalse, reason: 'the default');
      usePhotoPicker(android);
      expect(android.useAndroidPhotoPicker, isTrue);
    });

    test('tells videos from photos, with or without a type', () {
      expect(isPickedVideo('a.jpg', 'image/jpeg'), isFalse);
      expect(isPickedVideo('a', 'video/mp4'), isTrue);
      expect(isPickedVideo('clip.MP4', null), isTrue);
      expect(isPickedVideo('clip.mov', null), isTrue);
      expect(isPickedVideo('photo.heic', null), isFalse);
      expect(isPickedVideo('noextension', null), isFalse);
    });
  });

  group('choosing a time', () {
    test('the evening is only offered while it is ahead', () {
      final morning = quickTimes(DateTime(2026, 11, 6, 9));
      expect(morning.map((q) => q.label), [
        'In 1 hour',
        'Tonight, 8 PM',
        'Tomorrow, 8 AM',
      ]);
      expect(morning[1].at, DateTime(2026, 11, 6, 20));
      expect(morning[2].at, DateTime(2026, 11, 7, 8));

      final night = quickTimes(DateTime(2026, 11, 6, 21));
      expect(night.map((q) => q.label), ['In 1 hour', 'Tomorrow, 8 AM']);
    });

    test('tomorrow is right at the end of a month', () {
      final q = quickTimes(DateTime(2026, 11, 30, 21));
      expect(q.last.at, DateTime(2026, 12, 1, 8));
    });

    testWidgets('arrival times read naturally', (t) async {
      final now = DateTime(2026, 11, 6, 9);
      late List<String> out;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              out = [
                formatArrival(context, DateTime(2026, 11, 6, 20), now: now),
                formatArrival(context, DateTime(2026, 11, 7, 8), now: now),
                formatArrival(context, DateTime(2026, 12, 25, 8), now: now),
              ];
              return const SizedBox();
            },
          ),
        ),
      );
      expect(out[0], 'Today, 8:00 PM');
      expect(out[1], 'Tomorrow, 8:00 AM');
      expect(out[2], contains('Dec 25'));
    });
  });

  group('the composer', () {
    Future<_Server> show(
      WidgetTester t, {
      String initial = '',
      void Function()? onScheduled,
    }) async {
      t.view.physicalSize = const Size(500, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final server = _Server();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentAccountIdProvider.overrideWithValue('me'),
            scheduledMessageServiceProvider.overrideWithValue(server),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showScheduleComposer(
                    context,
                    recipientId: 'ann',
                    initialText: initial,
                    onScheduled: onScheduled,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return server;
    }

    testWidgets('says what is missing, and sends nothing until it is right', (
      t,
    ) async {
      final server = await show(t);
      await t.tap(find.byKey(const ValueKey('schedule-submit')));
      await t.pump();
      expect(find.text('Write your message first.'), findsOneWidget);
      expect(find.text('Choose when it should arrive.'), findsOneWidget);
      expect(server.rows, isEmpty);

      await t.enterText(find.byType(TextField), 'happy birthday');
      await t.pump();
      expect(find.text('Write your message first.'), findsNothing);
      await t.tap(find.text('In 1 hour'));
      await t.pump();
      expect(find.text('Choose when it should arrive.'), findsNothing);
      expect(find.textContaining('Arrives: '), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('schedule-submit')));
      await t.pumpAndSettle();
      expect(server.rows.single.content, 'happy birthday');
      expect(server.rows.single.recipientId, 'ann');
      final ahead = server.rows.single.sendAt.difference(DateTime.now());
      expect(ahead.inMinutes, inInclusiveRange(55, 60));
      expect(find.text('open'), findsOneWidget, reason: 'the sheet closed');
      expect(find.textContaining('Will arrive'), findsOneWidget);
    });

    testWidgets('starts with what you typed, and empties the box once done', (
      t,
    ) async {
      var cleared = 0;
      final server = await show(
        t,
        initial: 'typed already',
        onScheduled: () => cleared++,
      );
      expect(find.text('typed already'), findsOneWidget);
      await t.tap(find.text('Tomorrow, 8 AM'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('schedule-submit')));
      await t.pumpAndSettle();
      expect(server.rows.single.content, 'typed already');
      expect(cleared, 1);
    });

    testWidgets('the server saying no is shown, and nothing is lost', (
      t,
    ) async {
      var cleared = 0;
      final server = await show(
        t,
        initial: 'keep me',
        onScheduled: () => cleared++,
      );
      server.refuse = 'You already have 50 messages waiting.';
      await t.tap(find.text('In 1 hour'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('schedule-submit')));
      await t.pumpAndSettle();
      expect(find.textContaining('50 messages waiting'), findsOneWidget);
      expect(find.text('keep me'), findsOneWidget);
      expect(cleared, 0);
    });
  });

  group('the scheduled list, behind the paperclip', () {
    Future<(ProviderContainer, _Server)> show(WidgetTester t) async {
      t.view.physicalSize = const Size(500, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final server = _Server();
      final c = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          scheduledMessageServiceProvider.overrideWithValue(server),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showScheduledMessages(
                    context,
                    roomId: room,
                    recipientId: 'ann',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      return (c, server);
    }

    Future<void> open(WidgetTester t) async {
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('empty: says so, and offers a new one', (t) async {
      await show(t);
      await open(t);
      expect(find.byKey(const ValueKey('scheduled-empty')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('scheduled-new')));
      await t.pumpAndSettle();
      expect(find.text('SCHEDULE A MESSAGE'), findsOneWidget);
    });

    testWidgets('shows only this chat; a new one appears; one can be removed '
        'and the list stays open', (t) async {
      final (c, server) = await show(t);
      final soon = DateTime.now().add(const Duration(hours: 1));
      final n = c.read(scheduledMessagesProvider.notifier);
      await n.schedule(recipientId: 'someone', content: 'other', sendAt: soon);
      await n.schedule(recipientId: 'ann', content: 'hello', sendAt: soon);
      await open(t);
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('other'), findsNothing);

      await t.tap(find.byKey(const ValueKey('scheduled-new')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'another');
      await t.pump();
      await t.tap(find.text('In 1 hour'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('schedule-submit')));
      await t.pumpAndSettle();
      expect(find.text('another'), findsOneWidget);
      expect(server.rows.last.recipientId, 'ann');

      await t.tap(find.byKey(const ValueKey('scheduled-remove-s1')));
      await t.pumpAndSettle();
      expect(server.removed, ['s1']);
      expect(find.text('hello'), findsNothing);
      await t.tap(find.byKey(const ValueKey('scheduled-remove-s2')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('scheduled-empty')), findsOneWidget);
    });

    testWidgets('one that could not go says why', (t) async {
      final (c, server) = await show(t);
      server.rows.add(
        ScheduledMessage.fromJson({
          'id': 's9',
          'recipient_id': 'ann',
          'content': 'hello',
          'send_at': '2026-11-06T10:00:00Z',
          'status': 'failed',
          'reason': 'user_unavailable',
        }),
      );
      await c.read(scheduledMessagesProvider.notifier).refresh();
      await open(t);
      expect(find.text('This person is not available.'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
    });
  });

  group('going out', () {
    final libPath =
        '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
        'isar_community_flutter_libs-3.3.2/linux/libisar.so';
    final skip = File(libPath).existsSync()
        ? false
        : 'Isar native library not found';

    Future<(ProviderContainer, _Server, Isar)> setUpIsar() async {
      await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      final dir = Directory.systemTemp.createTempSync('scheduled');
      final isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 'sch${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        dir.deleteSync(recursive: true);
      });
      final server = _Server();
      final c = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          scheduledMessageServiceProvider.overrideWithValue(server),
          isarServiceProvider.overrideWithValue(
            IsarService.withDb(Future.value(isar))..accountId = 'me',
          ),
        ],
      );
      addTearDown(c.dispose);
      return (c, server, isar);
    }

    final sent = {
      'type': 'scheduled_update',
      'id': 's1',
      'recipient_id': 'ann',
      'content': 'good morning',
      'send_at': '2026-11-06T08:00:00Z',
      'sent_at': '2026-11-06T08:00:05Z',
      'status': 'sent',
      'message_id': 'real-1',
    };

    test('lands in the chat as your message, once, and is collected', () async {
      final (c, server, isar) = await setUpIsar();
      final n = c.read(scheduledMessagesProvider.notifier);
      await n.heard(sent);
      await n.heard(sent); // heard twice: no harm
      final rows = await isar.localMessages.where().findAll();
      final m = rows.single;
      expect(m.messageId, 'real-1');
      expect(m.roomId, room);
      expect(m.senderId, 'me');
      expect(m.textContent, 'good morning');
      expect(m.status, MessageStatus.sent);
      expect(server.removed, contains('s1'));
      expect(c.read(scheduledInRoomProvider(room)), isEmpty);
    }, skip: skip);

    test(
      'one that went out while the app was closed is found on reconnect',
      () async {
        final (c, server, isar) = await setUpIsar();
        server.rows.addAll([
          ScheduledMessage.fromJson(sent),
          ScheduledMessage(
            id: 's2',
            recipientId: 'ann',
            content: 'later',
            sendAt: DateTime.now().add(const Duration(days: 1)),
          ),
        ]);
        await c.read(scheduledMessagesProvider.notifier).refresh();
        final rows = await isar.localMessages.where().findAll();
        expect(rows.single.messageId, 'real-1');
        expect(server.removed, ['s1']);
        final waiting = c.read(scheduledInRoomProvider(room));
        expect(waiting.single.id, 's2');
      },
      skip: skip,
    );
  });
}
