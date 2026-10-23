import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/typing_providers.dart';
import 'package:serafim/src/utils/chat/typing_bubble.dart';
import 'package:serafim/src/utils/chat/typing_broadcaster.dart';

void main() {
  group('what we send', () {
    testWidgets('one "typing" for a burst of keys, then one "stopped"', (
      t,
    ) async {
      final sent = <bool>[];
      final b = TypingBroadcaster(send: sent.add);

      for (final text in ['h', 'he', 'hel', 'hell', 'hello']) {
        b.textChanged(text);
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(sent, [true], reason: 'not one frame per key');

      await t.pump(const Duration(seconds: 5)); // idle
      expect(sent, [true, false]);
    });

    testWidgets('a long typing spell repeats about every 3 seconds', (t) async {
      final sent = <bool>[];
      final b = TypingBroadcaster(send: sent.add);
      // 10 s of steady typing, a key every half second.
      for (var i = 0; i < 20; i++) {
        b.textChanged('x' * (i + 1));
        await t.pump(const Duration(milliseconds: 500));
      }
      expect(sent.where((s) => s).length, inInclusiveRange(3, 4));
      expect(sent.contains(false), isFalse, reason: 'still typing');
      b.dispose();
      expect(sent.last, isFalse);
    });

    testWidgets('clearing the box (or sending) stops at once, only once', (
      t,
    ) async {
      final sent = <bool>[];
      final b = TypingBroadcaster(send: sent.add);
      b.textChanged('hi');
      b.textChanged('');
      b.textChanged('   ');
      b.stop();
      expect(sent, [true, false]);
      await t.pump(const Duration(seconds: 10));
      expect(sent, [true, false], reason: 'no stray stop later');
    });

    testWidgets('never says "stopped" if it never said "typing"', (t) async {
      final sent = <bool>[];
      TypingBroadcaster(send: sent.add).stop();
      expect(sent, isEmpty);
    });
  });

  group('what we show', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [currentAccountIdProvider.overrideWithValue('me')],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('typing starts, stops, and works per conversation', () {
      final c = container();
      final room = c.read(typingProvider.notifier);
      room.heard({'sender_id': 'bob', 'state': true});
      expect(c.read(typingInRoomProvider('bob_me')), {'bob'});
      expect(c.read(typingInRoomProvider('al_me')), isEmpty);

      room.heard({'sender_id': 'bob', 'state': false});
      expect(c.read(typingInRoomProvider('bob_me')), isEmpty);
    });

    test('a group tracks several people', () {
      final c = container();
      final n = c.read(typingProvider.notifier);
      n.heard({'sender_id': 'a', 'group_id': 'g1', 'state': true});
      n.heard({'sender_id': 'b', 'group_id': 'g1', 'state': true});
      expect(c.read(typingInRoomProvider('group_g1')), {'a', 'b'});
      n.stopped('group_g1', 'a');
      expect(c.read(typingInRoomProvider('group_g1')), {'b'});
    });

    test('you never see yourself typing', () {
      final c = container();
      c.read(typingProvider.notifier).heard({'sender_id': 'me', 'state': true});
      expect(c.read(typingProvider), isEmpty);
    });

    testWidgets('a lost "stopped" cannot leave typing up forever', (t) async {
      final c = container();
      c.read(typingProvider.notifier).heard({'sender_id': 'bob'});
      expect(c.read(typingProvider), isNotEmpty);
      await t.pump(TypingNotifier.typingExpiry + const Duration(seconds: 1));
      expect(c.read(typingProvider), isEmpty);
    });

    testWidgets('steady typing keeps it up past the expiry', (t) async {
      final c = container();
      final n = c.read(typingProvider.notifier);
      for (var i = 0; i < 4; i++) {
        n.heard({'sender_id': 'bob', 'state': true});
        await t.pump(const Duration(seconds: 3));
      }
      expect(c.read(typingProvider), isNotEmpty);
      c.dispose(); // cancels the pending expiry
    });

    testWidgets('the bubble shows three dots and who is typing', (t) async {
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: TypingBubble(who: 'Ann'))),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Ann'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Ann is typing',
        ),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox()); // disposes the animation cleanly
    });
  });
}
