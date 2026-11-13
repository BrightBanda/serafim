import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/trim_range.dart';

void main() {
  const total = Duration(seconds: 60);

  test('a fresh range is the whole video and counts as untouched', () {
    final r = TrimRange.whole(total);
    expect(r.start, Duration.zero);
    expect(r.end, total);
    expect(r.isWhole, isTrue);
    expect(r.estimatedBytes(30 * 1024 * 1024), 30 * 1024 * 1024);
  });

  test('a few milliseconds off either end is still untouched', () {
    final r = TrimRange.whole(total)
        .withStart(const Duration(milliseconds: 80))
        .withEnd(total - const Duration(milliseconds: 90));
    expect(r.isWhole, isTrue);
  });

  test('moving either handle makes it a trim', () {
    expect(
      TrimRange.whole(total).withStart(const Duration(seconds: 5)).isWhole,
      isFalse,
    );
    expect(
      TrimRange.whole(total).withEnd(const Duration(seconds: 50)).isWhole,
      isFalse,
    );
  });

  test('the start cannot pass the end minus the shortest clip', () {
    final r = TrimRange.whole(total)
        .withEnd(const Duration(seconds: 10))
        .withStart(const Duration(seconds: 30));
    expect(r.start, const Duration(seconds: 9));
    expect(r.length, const Duration(seconds: 1));
  });

  test('the end cannot come before the start plus the shortest clip', () {
    final r = TrimRange.whole(total)
        .withStart(const Duration(seconds: 20))
        .withEnd(const Duration(seconds: 3));
    expect(r.end, const Duration(seconds: 21));
  });

  test('handles stay inside the video', () {
    final r = TrimRange.whole(total)
        .withStart(const Duration(seconds: -4))
        .withEnd(const Duration(seconds: 90));
    expect(r.start, Duration.zero);
    expect(r.end, total);
  });

  test('a video shorter than the minimum can still be kept whole', () {
    final r = TrimRange.whole(const Duration(milliseconds: 600));
    expect(r.isWhole, isTrue);
    expect(r.withStart(const Duration(milliseconds: 300)).start, Duration.zero);
  });

  test('the size estimate follows the length kept', () {
    final r = TrimRange.whole(total)
        .withStart(const Duration(seconds: 15))
        .withEnd(const Duration(seconds: 45));
    expect(r.estimatedBytes(40 * 1024 * 1024), 20 * 1024 * 1024);
  });

  test('with a limit, a long video starts as its first part', () {
    final r = TrimRange.whole(total, maxLength: const Duration(seconds: 20));
    expect(r.end, const Duration(seconds: 20));
    expect(r.isWhole, isFalse);
    // A video within the limit is still whole.
    expect(
      TrimRange.whole(
        const Duration(seconds: 15),
        maxLength: const Duration(seconds: 20),
      ).isWhole,
      isTrue,
    );
  });

  test('the limit holds whichever handle moves', () {
    const limit = Duration(seconds: 20);
    var r = TrimRange.whole(total, maxLength: limit);
    // Dragging the end on pushes against the limit.
    expect(r.withEnd(const Duration(seconds: 50)).end, limit);
    // Dragging the start back stops where the clip would be too long.
    r = r
        .withStart(const Duration(seconds: 10))
        .withEnd(const Duration(seconds: 30));
    expect(r.length, limit);
    expect(r.withStart(Duration.zero).start, const Duration(seconds: 10));
    expect(
      r.withEnd(const Duration(seconds: 60)).end,
      const Duration(seconds: 30),
    );
  });

  test('clock text', () {
    expect(formatClock(const Duration(seconds: 7)), '0:07');
    expect(formatClock(const Duration(seconds: 65)), '1:05');
    expect(formatClock(const Duration(seconds: 3729)), '1:02:09');
  });
}
