import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/emoji.dart';

void main() {
  group('telling emoji apart', () {
    test('plain, joined, flag, skin tone, keycap and symbol emoji', () {
      for (final e in [
        '😀',
        '👍🏽',
        '👨‍👩‍👧',
        '🇳🇬',
        '❤️',
        '✨',
        '⭐',
        '1️⃣',
        '🙂',
      ]) {
        expect(isEmoji(e), isTrue, reason: e);
      }
    });

    test('letters, digits, punctuation and text symbols are not', () {
      for (final e in ['a', 'Z', '1', '#', '!', ' ', '-', '©', '♥']) {
        expect(isEmoji(e), isFalse, reason: e);
      }
    });

    test('emoji-only messages are counted; anything else is null', () {
      expect(emojiOnlyCount('😀'), 1);
      expect(emojiOnlyCount('😀 😀😀'), 3);
      expect(emojiOnlyCount('👨‍👩‍👧👍🏽'), 2);
      expect(emojiOnlyCount('hi 😀'), isNull);
      expect(emojiOnlyCount('😀!'), isNull);
      expect(emojiOnlyCount(''), isNull);
      expect(emojiOnlyCount('   '), isNull);
    });

    test('fewer emoji are bigger; a wall of them is ordinary text', () {
      expect(jumboEmojiSize(1), 38);
      expect(jumboEmojiSize(3), 38);
      expect(jumboEmojiSize(4), 28);
      expect(jumboEmojiSize(6), 28);
      expect(jumboEmojiSize(7), isNull);
      expect(jumboEmojiSize(0), isNull);
    });

    test('emoji inside a sentence are enlarged, the words are not', () {
      final spans = emojiSizedSpans('hi 👍 ok', 11, 1.4);
      final big = spans.whereType<TextSpan>().where((s) => s.style != null);
      expect(big.map((s) => s.text), ['👍']);
      expect(big.single.style!.fontSize, closeTo(15.4, 0.001));
    });
  });

  group('in a bubble', () {
    Future<double?> sizeOf(WidgetTester t, String message) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              who: 'Ann',
              message: message,
              side: ChatBubbleSide.incoming,
            ),
          ),
        ),
      );
      final text = t.widget<Text>(find.text(message.trim()));
      return text.style?.fontSize;
    }

    testWidgets('three emoji alone are drawn large', (t) async {
      expect(await sizeOf(t, '😀😀😀'), 38);
    });

    testWidgets('a word and an emoji are ordinary-sized text', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              who: 'Ann',
              message: 'hello 😀',
              side: ChatBubbleSide.incoming,
            ),
          ),
        ),
      );
      final rich = t
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((w) => w.text.toPlainText().contains('hello'));
      final sizes = <String, double?>{};
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          sizes[span.text!] = span.style?.fontSize;
        }
        return true;
      });
      expect(sizes['😀'], closeTo(15.4, 0.001));
      // Only the emoji got a size of their own; the words inherit the
      // message's.
      expect(sizes['hello '], isNull);
    });

    test('gifs, webp and png are small media; jpeg photos are not', () {
      expect(isSmallMedia('/x/1.gif'), isTrue);
      expect(isSmallMedia('/x/1.WEBP'), isTrue);
      expect(isSmallMedia('/x/1.png'), isTrue);
      expect(isSmallMedia('/x/1.jpg'), isFalse);
    });
  });
}
