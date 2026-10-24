import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/view/draw_together_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/draw_together_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';

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

Map<String, dynamic> frame(
  String op, {
  String session = 'S',
  String from = 'ann',
  Map<String, dynamic>? extra,
}) => {
  'type': 'draw',
  'op': op,
  'session': session,
  'sender_id': from,
  ...?extra,
};

/// Ends the session shown in a page test, so no retry timer outlives it.
Future<void> _finish(WidgetTester tester) async {
  final c = ProviderScope.containerOf(
    tester.element(find.byType(DrawTogetherPage)),
  );
  c.read(drawTogetherProvider.notifier).close();
  await tester.pump();
}

void main() {
  group('starting', () {
    test('inviting sends the invite and waits', () {
      final t = make();
      expect(t.n.invite('ann'), isTrue);
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.waiting);
      expect(t.ws.sent.single['op'], 'invite');
      expect(t.ws.sent.single['recipient_id'], 'ann');
      expect(t.n.busy, isTrue);
      expect(t.n.invite('bob'), isFalse, reason: 'one session at a time');
    });

    test('no connection: it ends at once with a reason', () {
      final t = make();
      t.ws.up = false;
      expect(t.n.invite('ann'), isFalse);
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.ended);
      expect(t.n.busy, isFalse);
    });

    test('they join, and we are live', () {
      final t = make();
      t.n.invite('ann');
      final id = t.c.read(drawTogetherProvider)!.id;
      t.n.heard(frame('join', session: id));
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.live);
    });

    test('an invitation: a new one is reported, and accepting joins', () {
      final t = make();
      expect(t.n.heard(frame('invite')), isTrue);
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.invited);
      t.n.join();
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.live);
      expect(t.ws.sent.last['op'], 'join');
      expect(t.ws.sent.last['session'], 'S');
    });

    test('declining tells them and forgets it', () {
      final t = make();
      t.n.heard(frame('invite'));
      t.n.decline();
      expect(t.ws.sent.last['op'], 'decline');
      expect(t.c.read(drawTogetherProvider), isNull);
    });

    test(
      'busy: a second invitation is answered "busy" and changes nothing',
      () {
        final t = make();
        t.n.heard(frame('invite'));
        expect(t.n.heard(frame('invite', session: 'T', from: 'bob')), isFalse);
        expect(t.ws.sent.last['op'], 'busy');
        expect(t.ws.sent.last['recipient_id'], 'bob');
        expect(t.c.read(drawTogetherProvider)!.peerId, 'ann');
      },
    );

    testWidgets('no answer in 45 seconds ends it', (tester) async {
      final t = make();
      t.n.invite('ann');
      await tester.pump(const Duration(seconds: 46));
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.status, DrawStatus.ended);
      expect(s.endedBecause, 'No answer.');
    });
  });

  group('the shared sheet', () {
    ({ProviderContainer c, _FakeWs ws, DrawTogether n}) live() {
      final t = make();
      t.n.heard(frame('invite'));
      t.n.join();
      t.ws.sent.clear();
      return t;
    }

    test('their strokes arrive in pieces and join up', () {
      final t = live();
      t.n.heard(
        frame(
          'stroke',
          extra: {
            'id': '1',
            'c': 0xFFFF0000,
            'w': 0.02,
            'e': false,
            'p': [0.1, 0.1, 0.2, 0.2],
            'done': false,
          },
        ),
      );
      t.n.heard(
        frame(
          'stroke',
          extra: {
            'id': '1',
            'c': 0xFFFF0000,
            'w': 0.02,
            'e': false,
            'p': [0.3, 0.3],
            'done': true,
          },
        ),
      );
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.strokes, hasLength(1));
      expect(s.strokes.single.stroke.points, hasLength(3));
      expect(s.strokes.single.done, isTrue);
      expect(s.strokes.single.mine, isFalse);
      expect(s.strokes.single.stroke.color, const Color(0xFFFF0000));
    });

    test('their eraser arrives as an eraser', () {
      final t = live();
      t.n.heard(
        frame(
          'stroke',
          extra: {
            'id': '2',
            'c': 0xFF000000,
            'w': 0.05,
            'e': true,
            'p': [0.5, 0.5],
            'done': true,
          },
        ),
      );
      expect(
        t.c.read(drawTogetherProvider)!.strokes.single.stroke.erase,
        isTrue,
      );
    });

    test('their undo, clear and paper', () {
      final t = live();
      for (final id in ['1', '2']) {
        t.n.heard(
          frame(
            'stroke',
            extra: {
              'id': id,
              'c': 0xFF000000,
              'w': 0.02,
              'e': false,
              'p': [0.1, 0.1],
              'done': true,
            },
          ),
        );
      }
      t.n.heard(frame('undo', extra: {'id': '1'}));
      expect(t.c.read(drawTogetherProvider)!.strokes.map((s) => s.key), [
        'ann:2',
      ]);
      t.n.heard(frame('paper', extra: {'i': 2}));
      expect(t.c.read(drawTogetherProvider)!.paper, 2);
      t.n.heard(frame('clear'));
      expect(t.c.read(drawTogetherProvider)!.strokes, isEmpty);
    });

    test('frames from another session or person are ignored', () {
      final t = live();
      t.n.heard(
        frame(
          'stroke',
          session: 'OTHER',
          extra: {
            'id': '1',
            'c': 1,
            'w': 0.02,
            'p': [0.1, 0.1],
            'done': true,
          },
        ),
      );
      t.n.heard(
        frame(
          'stroke',
          from: 'mallory',
          extra: {
            'id': '1',
            'c': 1,
            'w': 0.02,
            'p': [0.1, 0.1],
            'done': true,
          },
        ),
      );
      expect(t.c.read(drawTogetherProvider)!.strokes, isEmpty);
    });

    testWidgets('my drawing is sent in small batches, normalised', (
      tester,
    ) async {
      final t = live();
      t.n.beginStroke(
        color: Colors.red,
        widthIndex: 1,
        erase: false,
        point: const Offset(0.1, 0.2),
      );
      t.n.extendStroke(const Offset(0.3, 0.4));
      t.n.extendStroke(const Offset(0.5, 0.6));
      expect(t.ws.sent, isEmpty, reason: 'batched, not one frame per point');
      await tester.pump(const Duration(milliseconds: 70));
      expect(t.ws.sent, hasLength(1));
      expect(t.ws.sent.single['p'], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
      expect(t.ws.sent.single['done'], false);
      expect(t.ws.sent.single['w'], closeTo(8 / referencePadWidth, 1e-9));

      t.n.extendStroke(const Offset(0.7, 0.8));
      t.n.endStroke();
      expect(t.ws.sent.last['done'], true);
      expect(t.ws.sent.last['p'], [0.7, 0.8]);
      expect(t.c.read(drawTogetherProvider)!.strokes.single.mine, isTrue);
      t.n.close();
    });

    testWidgets('the eraser is wider and marked', (tester) async {
      final t = live();
      t.n.beginStroke(
        color: Colors.black,
        widthIndex: 1,
        erase: true,
        point: const Offset(0.5, 0.5),
      );
      t.n.endStroke();
      expect(t.ws.sent.last['e'], true);
      expect(t.ws.sent.last['w'], closeTo(8 * 2.5 / referencePadWidth, 1e-9));
      t.n.close();
    });

    test('undo takes back only MY last line and tells them', () {
      final t = live();
      t.n.heard(
        frame(
          'stroke',
          extra: {
            'id': '9',
            'c': 1,
            'w': 0.02,
            'p': [0.1, 0.1],
            'done': true,
          },
        ),
      );
      t.n.beginStroke(
        color: Colors.red,
        widthIndex: 0,
        erase: false,
        point: const Offset(0.1, 0.1),
      );
      t.n.endStroke();
      t.ws.sent.clear();
      t.n.undo();
      expect(t.ws.sent.single['op'], 'undo');
      expect(t.c.read(drawTogetherProvider)!.strokes.map((s) => s.mine), [
        false,
      ]);
      t.n.undo(); // nothing of mine left: their line stays
      expect(t.c.read(drawTogetherProvider)!.strokes, hasLength(1));
    });

    test('leaving tells them and clears the session', () {
      final t = make();
      t.n.invite('ann');
      final id = t.c.read(drawTogetherProvider)!.id;
      t.n.heard(frame('join', session: id));
      t.ws.sent.clear();
      t.n.leave();
      expect(t.ws.sent.single['op'], 'leave');
      expect(t.c.read(drawTogetherProvider), isNull);
    });

    test('they leave: it ends with a reason and I can still send it', () {
      final t = live();
      t.n.heard(
        frame(
          'stroke',
          extra: {
            'id': '1',
            'c': 1,
            'w': 0.02,
            'p': [0.1, 0.1],
            'done': true,
          },
        ),
      );
      t.n.heard(frame('leave'));
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.status, DrawStatus.ended);
      expect(s.endedBecause, 'They left.');
      expect(s.strokes, hasLength(1), reason: 'the drawing is still there');
      expect(t.n.busy, isFalse);
    });

    test('unavailable and declined end the wait', () {
      final t = make();
      t.n.invite('ann');
      final id = t.c.read(drawTogetherProvider)!.id;
      t.n.heard(frame('unavailable', session: id));
      expect(
        t.c.read(drawTogetherProvider)!.endedBecause,
        contains('not available'),
      );
    });
  });

  group('the page', () {
    Future<_FakeWs> open(WidgetTester tester, {bool join = true}) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ws = _FakeWs();
      final c = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketServiceProvider.overrideWithValue(ws),
          knownPersonProvider.overrideWith((ref, id) => null),
        ],
      );
      addTearDown(c.dispose);
      c.read(drawTogetherProvider.notifier).heard(frame('invite'));
      if (join) c.read(drawTogetherProvider.notifier).join();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: DrawTogetherPage()),
        ),
      );
      await tester.pump();
      return ws;
    }

    testWidgets('an invitation offers Join and Not now', (tester) async {
      await open(tester, join: false);
      expect(find.byKey(const ValueKey('together-join')), findsOneWidget);
      expect(find.byKey(const ValueKey('together-decline')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pump();
      expect(find.byKey(const ValueKey('together-pad')), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('drawing shows up and unlocks Send to chat', (tester) async {
      final ws = await open(tester);
      expect(find.byKey(const ValueKey('draw-send-to-chat')), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('together-pad')),
        const Offset(80, 40),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('draw-send-to-chat')), findsOneWidget);
      expect(ws.ops.where((o) => o == 'stroke'), isNotEmpty);
      expect(find.byKey(const ValueKey('draw-eraser')), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('it fits a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ws = _FakeWs();
      final c = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketServiceProvider.overrideWithValue(ws),
          knownPersonProvider.overrideWith((ref, id) => null),
        ],
      );
      addTearDown(c.dispose);
      c.read(drawTogetherProvider.notifier)
        ..heard(frame('invite'))
        ..join();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: DrawTogetherPage()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _finish(tester);
    });

    testWidgets('when they leave, the page says so', (tester) async {
      await open(tester);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DrawTogetherPage)),
      );
      c.read(drawTogetherProvider.notifier).heard(frame('leave'));
      await tester.pump();
      expect(find.text('They left.'), findsOneWidget);
      expect(find.byKey(const ValueKey('draw-eraser')), findsNothing);
    });
  });

  group('when messages get lost on the way', () {
    testWidgets('the invitation is repeated until they answer, then stops', (
      tester,
    ) async {
      final t = make();
      t.n.invite('ann');
      expect(t.ws.ops, ['invite']);
      await tester.pump(DrawTogether.inviteRepeatEvery);
      expect(t.ws.ops, ['invite', 'invite']);
      await tester.pump(DrawTogether.inviteRepeatEvery);
      expect(t.ws.ops.where((o) => o == 'invite'), hasLength(3));

      final id = t.c.read(drawTogetherProvider)!.id;
      t.n.heard(frame('join', session: id));
      t.ws.sent.clear();
      await tester.pump(const Duration(seconds: 20));
      expect(t.ws.ops.where((o) => o == 'invite'), isEmpty, reason: 'answered');
      t.n.close();
    });

    testWidgets('it does not nag for ever', (tester) async {
      final t = make();
      t.n.invite('ann');
      await tester.pump(const Duration(seconds: 44));
      expect(
        t.ws.ops.where((o) => o == 'invite').length,
        lessThanOrEqualTo(DrawTogether.maxInviteSends),
      );
      await tester.pump(const Duration(seconds: 5));
    });

    test('a repeated invitation is not a new one', () {
      final t = make();
      expect(t.n.heard(frame('invite')), isTrue);
      expect(t.n.heard(frame('invite')), isFalse, reason: 'no second banner');
      expect(t.ws.sent, isEmpty, reason: 'and not answered "busy"');
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.invited);
    });

    test('they are drawing, so they have joined, even if "join" was lost', () {
      final t = make();
      t.n.invite('ann');
      final id = t.c.read(drawTogetherProvider)!.id;
      t.n.heard(
        frame(
          'stroke',
          session: id,
          extra: {
            'id': '1',
            'c': 1,
            'w': 0.02,
            'p': [0.1, 0.1],
            'done': true,
          },
        ),
      );
      final s = t.c.read(drawTogetherProvider)!;
      expect(s.status, DrawStatus.live);
      expect(s.strokes, hasLength(1), reason: 'and the line is kept');
    });

    test('a "ready" alone also starts it', () {
      final t = make();
      t.n.invite('ann');
      final id = t.c.read(drawTogetherProvider)!.id;
      t.n.heard(frame('ready', session: id));
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.live);
    });

    test('a join is answered "ready", every time', () {
      final t = make();
      t.n.invite('ann');
      final id = t.c.read(drawTogetherProvider)!.id;
      t.ws.sent.clear();
      t.n.heard(frame('join', session: id));
      t.n.heard(frame('join', session: id)); // a repeat
      expect(t.ws.ops, ['ready', 'ready']);
      expect(t.c.read(drawTogetherProvider)!.status, DrawStatus.live);
    });

    testWidgets('joining is repeated until they confirm', (tester) async {
      final t = make();
      t.n.heard(frame('invite'));
      t.n.join();
      expect(t.ws.ops.where((o) => o == 'join'), hasLength(1));
      await tester.pump(DrawTogether.joinRepeatEvery);
      expect(t.ws.ops.where((o) => o == 'join'), hasLength(2));

      t.n.heard(frame('ready'));
      t.ws.sent.clear();
      await tester.pump(const Duration(seconds: 10));
      expect(t.ws.ops, isEmpty, reason: 'confirmed: no more');
      t.n.close();
    });

    testWidgets('joining stops after a few tries if they never reply', (
      tester,
    ) async {
      final t = make();
      t.n.heard(frame('invite'));
      t.n.join();
      await tester.pump(const Duration(seconds: 30));
      expect(
        t.ws.ops.where((o) => o == 'join').length,
        DrawTogether.maxJoinSends,
      );
      t.n.close();
    });

    testWidgets('declining is sent three times, a second apart', (
      tester,
    ) async {
      final t = make();
      t.n.heard(frame('invite'));
      t.ws.sent.clear();
      t.n.decline();
      expect(t.ws.ops, ['decline']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(t.ws.ops, ['decline', 'decline', 'decline']);
      expect(t.ws.sent.every((f) => f['recipient_id'] == 'ann'), isTrue);
    });
  });

  group('two phones over a network that loses messages', () {
    testWidgets(
      'the first join and the first invite are lost and it still works',
      (tester) async {
        final a = _Relay('A');
        final b = _Relay('B');
        final ca = ProviderContainer(
          overrides: [
            currentAccountIdProvider.overrideWithValue('A'),
            webSocketServiceProvider.overrideWithValue(a),
          ],
        );
        final cb = ProviderContainer(
          overrides: [
            currentAccountIdProvider.overrideWithValue('B'),
            webSocketServiceProvider.overrideWithValue(b),
          ],
        );
        addTearDown(ca.dispose);
        addTearDown(cb.dispose);
        a.to = cb;
        b.to = ca;
        // The network eats the first invitation and the first two joins.
        a.dropOps = {'invite': 1};
        b.dropOps = {'join': 2};

        ca.read(drawTogetherProvider.notifier).invite('B');
        expect(
          cb.read(drawTogetherProvider),
          isNull,
          reason: 'first invite lost',
        );
        await tester.pump(DrawTogether.inviteRepeatEvery);
        expect(cb.read(drawTogetherProvider)?.status, DrawStatus.invited);

        cb.read(drawTogetherProvider.notifier).join();
        expect(
          ca.read(drawTogetherProvider)!.status,
          DrawStatus.waiting,
          reason: 'the first join was lost',
        );
        await tester.pump(DrawTogether.joinRepeatEvery);
        expect(
          ca.read(drawTogetherProvider)!.status,
          DrawStatus.waiting,
          reason: 'and the second',
        );
        await tester.pump(DrawTogether.joinRepeatEvery);
        expect(
          ca.read(drawTogetherProvider)!.status,
          DrawStatus.live,
          reason: 'the third got through',
        );
        await tester.pump(const Duration(seconds: 10));
        ca.read(drawTogetherProvider.notifier).close();
        cb.read(drawTogetherProvider.notifier).close();
      },
    );

    testWidgets('a decline that is lost once is still heard', (tester) async {
      final a = _Relay('A');
      final b = _Relay('B');
      final ca = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue('A'),
          webSocketServiceProvider.overrideWithValue(a),
        ],
      );
      final cb = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWithValue('B'),
          webSocketServiceProvider.overrideWithValue(b),
        ],
      );
      addTearDown(ca.dispose);
      addTearDown(cb.dispose);
      a.to = cb;
      b.to = ca;
      b.dropOps = {'decline': 2};

      ca.read(drawTogetherProvider.notifier).invite('B');
      cb.read(drawTogetherProvider.notifier).decline();
      expect(ca.read(drawTogetherProvider)!.status, DrawStatus.waiting);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(ca.read(drawTogetherProvider)!.status, DrawStatus.ended);
      expect(ca.read(drawTogetherProvider)!.endedBecause, 'They declined.');
    });
  });
}

/// A phone whose connection hands frames to the other phone, like the server,
/// and can be told to lose the first few frames of a kind.
class _Relay extends WebSocketService {
  _Relay(this.me);
  final String me;
  late ProviderContainer to;
  Map<String, int> dropOps = {};

  @override
  bool sendMessage(Map<String, dynamic> payload) {
    final op = payload['op'] as String?;
    if (op != null && (dropOps[op] ?? 0) > 0) {
      dropOps[op] = dropOps[op]! - 1;
      return true; // sent, but lost on the way
    }
    to
        .read(drawTogetherProvider.notifier)
        .heard({...payload, 'sender_id': me}..remove('recipient_id'));
    return true;
  }
}
