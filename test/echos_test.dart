import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/data/models/echo.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/echo_service.dart';
import 'package:serafim/src/presentation/view/echo_page.dart';
import 'package:serafim/src/presentation/view/widgets/echo_send_card.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/echo_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';

Echo echo({
  String id = 'e1',
  String text = 'Anyone up for football?',
  int minutes = 40,
  bool ended = false,
  int reached = 0,
}) => Echo(
  id: id,
  text: text,
  createdAt: DateTime.now().toUtc(),
  expiresAt: DateTime.now().toUtc().add(Duration(minutes: minutes)),
  user: const PublicUser(id: 'ann', username: 'ann', displayName: 'Ann'),
  ended: ended,
  sharedInterests: const ['Music', 'Sports'],
  reachedCount: reached,
);

class _Server extends EchoService {
  _Server({this.status = const MyEchoStatus(), Echo? received})
    : received = received ?? echo(),
      super(Dio());

  MyEchoStatus status;
  Echo received;
  final calls = <String>[];
  String? refuse;

  @override
  Future<MyEchoStatus> mine() async => status;

  @override
  Future<Echo> send({
    required String text,
    EchoAudience audience = EchoAudience.everyone,
    String? tag,
  }) async {
    calls.add('send $text ${audience.name} tag=$tag');
    if (refuse != null) throw ApiException(refuse!);
    final e = echo(id: 'mine', text: text, reached: 27);
    status = MyEchoStatus(echo: e, sentToday: 1);
    return e;
  }

  @override
  Future<Echo> latestFrom(String userId) async => received;

  @override
  Future<void> close(String id) async {
    calls.add('close $id');
    status = MyEchoStatus(sentToday: 1, echo: echo(id: id, ended: true));
  }

  @override
  Future<void> hide(String userId) async => calls.add('hide $userId');
}

class _Profile extends ProfileViewModel {
  _Profile(this.visibility);
  final EchoVisibility visibility;

  @override
  FutureOr<Profile?> build() => Profile(
    userId: 'me',
    displayName: 'Me',
    username: 'me',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    echoVisibility: visibility,
  );
}

Future<void> _show(
  WidgetTester t,
  _Server server,
  Widget child, {
  EchoVisibility visibility = EchoVisibility.everyone,
}) async {
  t.view.physicalSize = const Size(900, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        echoServiceProvider.overrideWithValue(server),
        profileViewModelProvider.overrideWith(() => _Profile(visibility)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                child,
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EchoPage(fromUserId: 'ann'),
                    ),
                  ),
                  child: const Text('open echo'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('an Echo reads what it needs', () {
    final now = DateTime.utc(2026, 11, 4, 12);
    final e = Echo.fromJson({
      'id': 'e1',
      'text': 'Up for a chat',
      'created_at': '2026-11-04T11:50:00+00:00',
      'expires_at': '2026-11-04T12:10:30+00:00',
      'user': {'id': 'u1', 'username': 'ann', 'display_name': 'Ann'},
      'shared_interests': ['Sports'],
      'reached_count': 30,
      'ended': false,
    });
    expect(e.minutesLeft(now), 11);
    expect(e.sharedInterests, ['Sports']);
    expect(e.reachedCount, 30);
    expect(
      MyEchoStatus.fromJson({'sent_today': 3, 'per_day': 3}).dailyLimitReached,
      isTrue,
    );
    expect(NotificationKind.parse('echo'), NotificationKind.echoReceived);
  });

  testWidgets('sending an Echo to new people only', (t) async {
    final server = _Server();
    await _show(t, server, const EchoSendCard());
    expect(find.text('Up for a chat?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('echo-send')));
    await t.pumpAndSettle();
    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('echo-text')),
        matching: find.byType(TextField),
      ),
      'Talk music?',
    );
    await t.tap(find.byKey(const ValueKey('echo-audience-strangers')));
    await t.pump();
    // No interest to pick any more.
    expect(find.text('Music'), findsNothing);
    await t.tap(find.byKey(const ValueKey('echo-post')));
    await t.pumpAndSettle();
    expect(server.calls, ['send Talk music? strangers tag=null']);
    expect(find.text('Your Echo reached 27 people.'), findsOneWidget);
    // The card now shows how it is doing.
    expect(find.textContaining('Reached 27'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('echo-end')));
    await t.pumpAndSettle();
    expect(server.calls.last, 'close mine');
    expect(find.text('Up for a chat?'), findsOneWidget);
  });

  testWidgets('sending to friends only', (t) async {
    final server = _Server();
    await _show(t, server, const EchoSendCard());
    await t.tap(find.byKey(const ValueKey('echo-send')));
    await t.pumpAndSettle();
    expect(find.textContaining('next 30 minutes'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('echo-audience-friends')));
    await t.pump();
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('echo-post')));
    await t.pumpAndSettle();
    expect(server.calls, ['send hi friends tag=null']);
  });

  testWidgets('sending with nothing written says so, in red', (t) async {
    final server = _Server();
    await _show(t, server, const EchoSendCard());
    await t.tap(find.byKey(const ValueKey('echo-send')));
    await t.pumpAndSettle();
    Border border() {
      final box = t.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('echo-text')),
              matching: find.byType(Container),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).border as Border;
    }

    final calm = border().top.color;
    expect(find.byKey(const ValueKey('field-error')), findsNothing);

    await t.tap(find.byKey(const ValueKey('echo-post')));
    await t.pump();
    expect(server.calls, isEmpty);
    expect(find.text('Write a short message first.'), findsOneWidget);
    expect(border().top.color, Colors.red.shade400);

    // Spaces are still nothing.
    await t.enterText(find.byType(TextField), '   ');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('echo-post')));
    await t.pump();
    expect(find.text('Write a short message first.'), findsOneWidget);
    expect(server.calls, isEmpty);

    // Typing clears it, and it can go.
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    expect(find.text('Write a short message first.'), findsNothing);
    expect(border().top.color, calm);
    await t.tap(find.byKey(const ValueKey('echo-post')));
    await t.pumpAndSettle();
    expect(server.calls, isNotEmpty);
  });

  testWidgets('limits are explained and stop sending', (t) async {
    final server = _Server(status: const MyEchoStatus(sentToday: 3, perDay: 3));
    await _show(t, server, const EchoSendCard());
    await t.tap(find.byKey(const ValueKey('echo-send')));
    await t.pumpAndSettle();
    expect(find.textContaining("That's 3 Echos today"), findsOneWidget);
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('echo-post')));
    await t.pump();
    expect(server.calls, isEmpty);
  });

  testWidgets('the server saying no is shown', (t) async {
    final server = _Server()
      ..refuse = 'Nobody who shares your interests can get an Echo right now.';
    await _show(t, server, const EchoSendCard());
    await t.tap(find.byKey(const ValueKey('echo-send')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('echo-post')));
    await t.pumpAndSettle();
    expect(find.textContaining('Nobody who shares'), findsOneWidget);
  });

  testWidgets('no card at all when Echos are off', (t) async {
    await _show(
      t,
      _Server(),
      const EchoSendCard(),
      visibility: EchoVisibility.off,
    );
    expect(find.text('Up for a chat?'), findsNothing);
  });

  testWidgets('a received Echo opens as a card with a choice', (t) async {
    final server = _Server();
    await _show(t, server, const SizedBox());
    await t.tap(find.text('open echo'));
    await t.pumpAndSettle();
    expect(find.text('Anyone up for football?'), findsOneWidget);
    expect(find.text('You both like Music, Sports'), findsOneWidget);
    expect(find.byKey(const ValueKey('echo-start-chat')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('echo-not-now')));
    await t.pumpAndSettle();
    expect(find.byType(EchoPage), findsNothing);
  });

  testWidgets('an ended Echo can only be closed, and its sender hidden', (
    t,
  ) async {
    final server = _Server(received: echo(ended: true));
    await _show(t, server, const SizedBox());
    await t.tap(find.text('open echo'));
    await t.pumpAndSettle();
    expect(find.text('This Echo has ended.'), findsOneWidget);
    expect(find.byKey(const ValueKey('echo-start-chat')), findsNothing);
    await t.tap(find.byKey(const ValueKey('echo-hide')));
    await t.pumpAndSettle();
    expect(server.calls, ['hide ann']);
    expect(find.textContaining("won't get Echos from Ann"), findsOneWidget);
  });
}
