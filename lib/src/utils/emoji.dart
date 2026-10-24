import 'package:flutter/widgets.dart';

/// Emoji handling for message text: telling emoji from letters, so they can
/// be drawn larger (and a message of nothing but emoji larger still).

/// Single characters that are emoji by default, outside the big pictograph
/// block (these need no variation selector to look like an emoji).
const List<(int, int)> _bmpEmoji = [
  (0x231A, 0x231B),
  (0x23E9, 0x23EC),
  (0x23F0, 0x23F0),
  (0x23F3, 0x23F3),
  (0x25FD, 0x25FE),
  (0x2614, 0x2615),
  (0x2648, 0x2653),
  (0x267F, 0x267F),
  (0x2693, 0x2693),
  (0x26A1, 0x26A1),
  (0x26AA, 0x26AB),
  (0x26BD, 0x26BE),
  (0x26C4, 0x26C5),
  (0x26CE, 0x26CE),
  (0x26D4, 0x26D4),
  (0x26EA, 0x26EA),
  (0x26F2, 0x26F3),
  (0x26F5, 0x26F5),
  (0x26FA, 0x26FA),
  (0x26FD, 0x26FD),
  (0x2705, 0x2705),
  (0x270A, 0x270B),
  (0x2728, 0x2728),
  (0x274C, 0x274C),
  (0x274E, 0x274E),
  (0x2753, 0x2755),
  (0x2757, 0x2757),
  (0x2795, 0x2797),
  (0x27B0, 0x27B0),
  (0x27BF, 0x27BF),
  (0x2B1B, 0x2B1C),
  (0x2B50, 0x2B50),
  (0x2B55, 0x2B55),
];

/// Whether [grapheme] (one user-perceived character) is an emoji: a pictograph,
/// a flag, a keycap, or anything asked to look like an emoji (variation
/// selector U+FE0F), including joined sequences such as 👨‍👩‍👧 and 👍🏽.
bool isEmoji(String grapheme) {
  final runes = grapheme.runes;
  if (runes.isEmpty) return false;
  if (runes.contains(0xFE0F) || runes.contains(0x20E3)) return true;
  final first = runes.first;
  if (first >= 0x1F000 && first <= 0x1FAFF) return true; // pictographs, flags
  for (final (lo, hi) in _bmpEmoji) {
    if (first >= lo && first <= hi) return true;
  }
  return false;
}

/// How many emoji [text] is made of, if it is *only* emoji (spaces and line
/// breaks aside); otherwise null. "👍👍" → 2, "hi 👍" → null, "" → null.
int? emojiOnlyCount(String text) {
  var count = 0;
  for (final g in text.characters) {
    if (g.trim().isEmpty) continue;
    if (!isEmoji(g)) return null;
    count++;
  }
  return count == 0 ? null : count;
}

/// A message of at most this many emoji, and nothing else, is shown large.
const int jumboEmojiMax = 6;

/// The font size for an emoji-only message of [count] emoji, or null when it
/// should be drawn like ordinary text. Fewer emoji, bigger.
double? jumboEmojiSize(int count) {
  if (count < 1 || count > jumboEmojiMax) return null;
  return count <= 3 ? 26 : 20;
}

/// How much larger emoji are drawn inside ordinary text.
const double emojiInTextScale = 1.4;

/// [text] as spans, with each emoji drawn [scale] times larger than [base].
List<InlineSpan> emojiSizedSpans(String text, double base, double scale) {
  final spans = <InlineSpan>[];
  final plain = StringBuffer();
  void flush() {
    if (plain.isEmpty) return;
    spans.add(TextSpan(text: plain.toString()));
    plain.clear();
  }

  for (final g in text.characters) {
    if (isEmoji(g)) {
      flush();
      spans.add(
        TextSpan(
          text: g,
          style: TextStyle(fontSize: base * scale),
        ),
      );
    } else {
      plain.write(g);
    }
  }
  flush();
  return spans;
}
