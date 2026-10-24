import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/view/draw_together_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/draw_together_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWs extends WebSocketService {
  final sent = <Map<String, dynamic>>[];
  bool up = true;

  @override
  bool sendMessage(Map<String, dynamic> payload) {
    if (!up) return false;
    sent.add(payload);
    return true;
  }

  List<String> get ops => [for (final f in sent) f['op'] as String];
}

({ProviderContainer c, _FakeWs ws, DrawTogether n}) make() {
  final ws = _FakeWs();
  final c = ProviderContainer(
    overrides: [
      currentAccountIdProvider.overrideWithValue('me'),
      webSocketServiceProvider.overrideWithValue(ws),
    ],
  );
  addTearDown(c.dispose);
  return (c: c, ws: ws, n: c.read(drawTogetherProvider.notifier));
}

/// A frame from the server.
Map<String, dynamic> server(
  String op, [
  Map<String, dynamic> extra = const {},
]) => {'type': 'draw', 'op': op, ...extra};

Map<String, dynamic> started({
  String session = 'S',
  String peer = 'ann',
  int paper = 0,
  List<Map<String, dynamic>> strokes = const [],
}) => server('started', {
  'session': session,
  'peer_id': peer,
  'status': 'live',
  'paper': paper,
  'strokes': strokes,
});

/// Inviting Ann, and the server starting it once she joins.
DrawTogether live(({ProviderContainer c, _FakeWs ws, DrawTogether n}) t) {
  t.n.invite('ann');
  t.n.heard(server('invited', {'session': 'S', 'peer_id': 'ann'}));
  t.n.heard(started());
  return t.n;
}

void main() {
  group('inviting', () {
    test('asks the server and waits for it to name the session', () {
      final t = make();
      expect(t.n.invite('ann'), isTrue);
      expect(t.ws.sent.single, {
        'type': 'draw',
        'op': 'invite',
        'recipient_id': 'ann',
      });
      var s = t.c.read(drawTogetherProvider)!;
      expect([s.status, s.id], [DrawStatus.waiting, null]);

      t.n.heard(server('invited', {'session': 'S', 'peer_id': 'ann'}));
      s = t.c.read(drawTogetherProvider)!;
      expect([s.status, s.id], [DrawStatus.waiting, 'S']);
      expect(t.n.invite('bob'), isFalse, reason: 'one session at a time');
      expect(t.ws.sent, hasLength(1), reason: 'nothing is repeated');
    });

    test('no connection: it ends at once with a reason', () {
      final t = make();
      t.ws.up = false;
      expect(t.n.invite('ann'), isFalse);
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.status, DrawStatus.ended);
      expect(s.endedBecause, contains('connection'));
    });

    test('the server starts it when they join, with the canvas', () {
      final t = make();
      live(t);
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.status, DrawStatus.live);
      expect(s.strokes, isEmpty);
    });

    test('refused, declined and expired end the wait with the reason', () {
      for (final (frame, words) in [
        (server('refused', {'peer_id': 'ann', 'reason': 'busy'}), 'already'),
        (server('ended', {'session': 'S', 'reason': 'declined'}), 'not now'),
        (server('ended', {'session': 'S', 'reason': 'expired'}), 'expired'),
      ]) {
        final t = make();
        t.n.invite('ann');
        t.n.heard(server('invited', {'session': 'S', 'peer_id': 'ann'}));
        t.n.heard(frame);
        final s = t.c.read(drawTogetherProvider)!;
        expect(s.status, DrawStatus.ended);
        expect(s.endedBecause, contains(words));
      }
    });

    test('cancelling before the server named it withdraws it once named', () {
      final t = make();
      t.n.invite('ann');
      t.n.leave();
      expect(t.c.read(drawTogetherProvider), isNull);
      t.n.heard(server('invited', {'session': 'S', 'peer_id': 'ann'}));
      expect(t.ws.sent.last, {'type': 'draw', 'op': 'leave', 'session': 'S'});
    });

    testWidgets('if the server never answers, it gives up on its own', (
      tester,
    ) async {
      final t = make();
      t.n.invite('ann');
      await tester.pump(DrawTogether.inviteWaits);
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.ended);
    });
  });

  group('being invited', () {
    test('a new invitation is reported once, and joining asks the server', () {
      final t = make();
      final invite = server('invite', {
        'session': 'S',
        'peer_id': 'ann',
        'expires_in': 60,
      });
      expect(t.n.heard(invite), isTrue);
      // It can arrive twice (live and on connect): the same one is not new.
      expect(t.n.heard(invite), isFalse);
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.invited);

      t.n.join();
      expect(t.ws.sent.single, {'type': 'draw', 'session': 'S', 'op': 'join'});
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.joining);
      t.n.heard(started());
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.live);
    });

    test('declining tells the server once and forgets it', () {
      final t = make();
      t.n.heard(server('invite', {'session': 'S', 'peer_id': 'ann'}));
      t.n.decline();
      expect(t.ws.ops, ['decline']);
      expect(t.c.read(drawTogetherProvider), isNull);
    });

    test('from a tapped push: shown at once, then the server confirms', () {
      final t = make();
      t.n.expectInvite(session: 'S', peerId: 'ann');
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.invited);
      // The connection then delivers the same invitation: not a new one.
      expect(
        t.n.heard(server('invite', {'session': 'S', 'peer_id': 'ann'})),
        isFalse,
      );
    });

    test('joining one that has gone is told so', () {
      final t = make();
      t.n.expectInvite(session: 'S', peerId: 'ann');
      t.n.join();
      t.n.heard(server('ended', {'session': 'S', 'reason': 'gone'}));
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.status, DrawStatus.ended);
      expect(s.endedBecause, contains('already ended'));
    });

    testWidgets('an invitation nobody answers goes away', (tester) async {
      final t = make();
      t.n.heard(
        server('invite', {'session': 'S', 'peer_id': 'ann', 'expires_in': 10}),
      );
      await tester.pump(const Duration(seconds: 16));
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.ended);
    });
  });

  group('drawing', () {
    test('their strokes arrive in pieces and join up', () {
      final t = make();
      live(t);
      final piece = {
        'session': 'S',
        'id': '1',
        'c': 0xFFFF0000,
        'w': 0.02,
        'e': false,
      };
      t.n.heard(
        server('stroke', {
          ...piece,
          'p': [0.1, 0.1],
          'done': false,
        }),
      );
      t.n.heard(
        server('stroke', {
          ...piece,
          'p': [0.2, 0.2],
          'done': true,
        }),
      );
      final s = t.c.read(drawTogetherProvider)!.strokes.single;
      expect(s.key, 'ann:1');
      expect(s.mine, isFalse);
      expect(s.stroke.points, [const Offset(0.1, 0.1), const Offset(0.2, 0.2)]);
      expect(s.done, isTrue);
      expect(s.stroke.color, const Color(0xFFFF0000));
    });

    test('their undo, clear and paper', () {
      final t = make();
      live(t);
      for (final id in ['1', '2']) {
        t.n.heard(
          server('stroke', {
            'session': 'S',
            'id': id,
            'c': 1,
            'w': 0.02,
            'p': [0.1, 0.1],
            'done': true,
          }),
        );
      }
      t.n.heard(server('undo', {'session': 'S', 'id': '1'}));
      expect(t.c.read(drawTogetherProvider)!.strokes.map((s) => s.key), [
        'ann:2',
      ]);
      t.n.heard(server('paper', {'session': 'S', 'i': 3}));
      expect(t.c.read(drawTogetherProvider)!.paper, 3);
      t.n.heard(server('clear', {'session': 'S'}));
      expect(t.c.read(drawTogetherProvider)!.strokes, isEmpty);
    });

    test('frames for another session are ignored', () {
      final t = make();
      live(t);
      t.n.heard(server('clear', {'session': 'OTHER'}));
      t.n.heard(server('ended', {'session': 'OTHER', 'reason': 'left'}));
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.live);
    });

    testWidgets('my drawing goes out in small batches, in the session', (
      tester,
    ) async {
      final t = make();
      live(t);
      t.ws.sent.clear();
      t.n.beginStroke(
        color: const Color(0xFF000000),
        widthIndex: 0,
        erase: false,
        point: const Offset(0.1, 0.1),
      );
      t.n.extendStroke(const Offset(0.2, 0.2));
      await tester.pump(DrawTogether.flushEvery);
      t.n.extendStroke(const Offset(0.3, 0.3));
      t.n.endStroke();
      expect(t.ws.ops, ['stroke', 'stroke']);
      expect(t.ws.sent.first['session'], 'S');
      expect(t.ws.sent.first['p'], [0.1, 0.1, 0.2, 0.2]);
      expect(t.ws.sent.last['p'], [0.3, 0.3]);
      expect(t.ws.sent.last['done'], isTrue);
    });

    test('undo takes back only my last line and tells them', () {
      final t = make();
      live(t);
      t.n.beginStroke(
        color: const Color(0xFF000000),
        widthIndex: 0,
        erase: false,
        point: const Offset(0.1, 0.1),
      );
      t.n.endStroke();
      t.n.heard(
        server('stroke', {
          'session': 'S',
          'id': '0',
          'c': 1,
          'w': 0.02,
          'p': [0.5, 0.5],
          'done': true,
        }),
      );
      t.n.undo();
      expect(t.c.read(drawTogetherProvider)!.strokes.single.key, 'ann:0');
      expect(t.ws.sent.last, {
        'type': 'draw',
        'session': 'S',
        'op': 'undo',
        'id': '0',
      });
    });

    test('a reconnect hands back the whole canvas, mine included', () {
      final t = make();
      live(t);
      t.n.heard(server('away', {'session': 'S'}));
      expect(t.c.read(drawTogetherProvider)!.peerAway, isTrue);
      t.n.heard(
        server('state', {
          'session': 'S',
          'peer_id': 'ann',
          'status': 'live',
          'paper': 2,
          'strokes': [
            {
              'owner': 'me',
              'id': '4',
              'c': 1,
              'w': 0.02,
              'p': [0.1, 0.1],
            },
            {
              'owner': 'ann',
              'id': '0',
              'c': 2,
              'w': 0.02,
              'p': [0.2, 0.2],
            },
          ],
        }),
      );
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.peerAway, isFalse);
      expect(s.paper, 2);
      expect(s.strokes.map((x) => (x.key, x.mine)), [
        ('me:4', true),
        ('ann:0', false),
      ]);
      // My next line does not reuse an id already on the sheet.
      t.n.beginStroke(
        color: const Color(0xFF000000),
        widthIndex: 0,
        erase: false,
        point: const Offset(0.3, 0.3),
      );
      expect(t.c.read(drawTogetherProvider)!.strokes.last.key, 'me:5');
      t.n.endStroke();
    });

    test('leaving tells them and clears the session', () {
      final t = make();
      live(t);
      t.n.leave();
      expect(t.ws.sent.last, {'type': 'draw', 'session': 'S', 'op': 'leave'});
      expect(t.c.read(drawTogetherProvider), isNull);
    });

    test('they leave: it ends with a reason, the drawing stays', () {
      final t = make();
      live(t);
      t.n.beginStroke(
        color: const Color(0xFF000000),
        widthIndex: 0,
        erase: false,
        point: const Offset(0.1, 0.1),
      );
      t.n.endStroke();
      t.n.heard(server('ended', {'session': 'S', 'reason': 'left'}));
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.status, DrawStatus.ended);
      expect(s.endedBecause, 'They left.');
      expect(s.strokes, hasLength(1));
    });
  });

  group('the page', () {
    Future<ProviderContainer> showPage(
      WidgetTester tester,
      void Function(DrawTogether n) setUp,
    ) async {
      final ws = _FakeWs();
      final c = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketServiceProvider.overrideWithValue(ws),
          knownPersonProvider.overrideWith((ref, id) => null),
        ],
      );
      addTearDown(c.dispose);
      setUp(c.read(drawTogetherProvider.notifier));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: DrawTogetherPage()),
        ),
      );
      await tester.pump();
      return c;
    }

    testWidgets('an invitation offers Join and Not now', (tester) async {
      final c = await showPage(
        tester,
        (n) => n.heard(server('invite', {'session': 'S', 'peer_id': 'ann'})),
      );
      expect(find.byKey(const ValueKey('together-join')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pump();
      expect(find.textContaining('Joining'), findsOneWidget);
      c.read(drawTogetherProvider.notifier).close();
      await tester.pump();
    });

    testWidgets('a declined invitation says so instead of a blank canvas', (
      tester,
    ) async {
      await showPage(tester, (n) {
        n.invite('ann');
        n.heard(server('invited', {'session': 'S', 'peer_id': 'ann'}));
        n.heard(server('ended', {'session': 'S', 'reason': 'declined'}));
      });
      expect(find.text('They said not now.'), findsOneWidget);
      expect(find.byKey(const ValueKey('together-pad')), findsNothing);
    });

    testWidgets('a dropped friend is shown while the server waits', (
      tester,
    ) async {
      final c = await showPage(tester, (n) {
        n.invite('ann');
        n.heard(server('invited', {'session': 'S', 'peer_id': 'ann'}));
        n.heard(started());
        n.heard(server('away', {'session': 'S'}));
      });
      expect(find.textContaining('lost their connection'), findsOneWidget);
      c.read(drawTogetherProvider.notifier).close();
      await tester.pump();
    });
  });

  // The bug that made invitations "not work": the frames were routed by a
  // provider listener, which Riverpod pauses when the screen holding it is
  // covered by another page — like the Draw Together page itself. A "join"
  // then sat unheard until the page closed.
  testWidgets('frames still arrive while a full-screen page covers the app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final socketIn = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(socketIn.close);
    final nav = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketEventsProvider.overrideWith((ref) => socketIn.stream),
          webSocketServiceProvider.overrideWithValue(_FakeWs()),
          knownPersonProvider.overrideWith((ref, id) => null),
        ],
        child: MaterialApp(
          navigatorKey: nav,
          // Like the main screen: the only thing keeping the view model on.
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(chatViewModelProvider);
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('home')),
    );
    final draw = container.read(drawTogetherProvider.notifier);

    // I invite Ann; the waiting page covers everything.
    draw.invite('ann');
    unawaited(openDrawTogether(nav.currentState!));
    // The waiting spinner never settles, so step through the transition.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The home screen is covered: its tickers are off, which is what makes
    // Riverpod pause its subscriptions.
    final home = tester.element(find.text('home', skipOffstage: false));
    expect(TickerMode.valuesOf(home).enabled, isFalse);

    socketIn.add(server('invited', {'session': 'S', 'peer_id': 'ann'}));
    socketIn.add(started());
    await tester.pump();
    await tester.pump();

    expect(container.read(drawTogetherProvider)!.status, DrawStatus.live);
    expect(find.byKey(const ValueKey('together-pad')), findsOneWidget);
    draw.close();
    await tester.pump(const Duration(seconds: 1));
  });
}
