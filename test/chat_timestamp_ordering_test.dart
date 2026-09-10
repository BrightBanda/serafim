import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';

/// Helper matching the exact sorting logic used in ChatThreadPage
List<LocalMessage> sortMessagesOldestFirst(List<LocalMessage> messages) {
  final sorted = [...messages];
  sorted.sort((a, b) {
    final timestampComparison = a.timestamp.compareTo(b.timestamp);
    if (timestampComparison != 0) {
      return timestampComparison;
    }
    return a.id.compareTo(b.id);
  });
  return sorted;
}

void main() {
  group('Chat Server Timestamp Parsing', () {
    test('parses ISO-8601 with +00:00 offset into UTC DateTime', () {
      const raw = '2026-09-08T05:57:57.312901+00:00';
      final parsed = parseServerTimestamp(raw);

      expect(parsed.isUtc, isTrue);
      expect(parsed.year, equals(2026));
      expect(parsed.month, equals(9));
      expect(parsed.day, equals(8));
      expect(parsed.hour, equals(5));
      expect(parsed.minute, equals(57));
      expect(parsed.second, equals(57));
      expect(parsed.millisecond, equals(312));
      expect(parsed.microsecond, equals(901));
    });

    test('parses ISO-8601 with Z suffix into UTC DateTime', () {
      const raw = '2026-09-08T06:33:16.022118Z';
      final parsed = parseServerTimestamp(raw);

      expect(parsed.isUtc, isTrue);
      expect(parsed.hour, equals(6));
      expect(parsed.minute, equals(33));
      expect(parsed.second, equals(16));
    });

    test('parses ISO-8601 with non-UTC offset into equivalent UTC DateTime', () {
      // 07:57 at UTC+2 is 05:57 UTC
      const raw = '2026-09-08T07:57:57.312901+02:00';
      final parsed = parseServerTimestamp(raw);

      expect(parsed.isUtc, isTrue);
      expect(parsed.hour, equals(5));
      expect(parsed.minute, equals(57));
      expect(parsed.second, equals(57));
    });

    test('normalizes naive ISO-8601 without offset as UTC', () {
      const raw = '2026-09-08T05:57:57.312901';
      final parsed = parseServerTimestamp(raw);

      expect(parsed.isUtc, isTrue);
      expect(parsed.hour, equals(5));
      expect(parsed.minute, equals(57));
      expect(parsed.second, equals(57));
    });

    test('returns current UTC time when timestamp is null or empty', () {
      final before = DateTime.now().toUtc();
      final fromNull = parseServerTimestamp(null);
      final fromEmpty = parseServerTimestamp('');
      final after = DateTime.now().toUtc();

      expect(fromNull.isUtc, isTrue);
      expect(fromEmpty.isUtc, isTrue);
      expect(fromNull.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(fromNull.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('Chat Message Deterministic Ordering', () {
    test('sorts messages chronologically by timestamp', () {
      final m1 = LocalMessage()
        ..id = 1
        ..messageId = 'msg-1'
        ..timestamp = DateTime.utc(2026, 9, 8, 8, 30, 0);

      final m2 = LocalMessage()
        ..id = 2
        ..messageId = 'msg-2'
        ..timestamp = DateTime.utc(2026, 9, 8, 8, 31, 0);

      final m3 = LocalMessage()
        ..id = 3
        ..messageId = 'msg-3'
        ..timestamp = DateTime.utc(2026, 9, 8, 8, 32, 0);

      final unordered = [m3, m1, m2];
      final ordered = sortMessagesOldestFirst(unordered);

      expect(ordered.map((m) => m.messageId).toList(), equals(['msg-1', 'msg-2', 'msg-3']));
    });

    test('resolves identical timestamps deterministically using Isar id tiebreaker', () {
      final sharedTime = DateTime.utc(2026, 9, 8, 8, 30, 0);

      final m1 = LocalMessage()
        ..id = 5
        ..messageId = 'older-local-row'
        ..timestamp = sharedTime;

      final m2 = LocalMessage()
        ..id = 10
        ..messageId = 'newer-local-row'
        ..timestamp = sharedTime;

      final unordered = [m2, m1];
      final ordered = sortMessagesOldestFirst(unordered);

      expect(ordered[0].id, equals(5));
      expect(ordered[1].id, equals(10));
    });
  });

  group('Event Queue Fault Tolerance and Serialization', () {
    test('event queue continues processing subsequent events even if one throws', () async {
      final processedEvents = <String>[];
      Future<void> eventQueue = Future.value();

      void queueTask(String id, {bool shouldFail = false}) {
        eventQueue = eventQueue
            .then((_) async {
              if (shouldFail) {
                throw StateError('Simulated processing failure for $id');
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
              processedEvents.add(id);
            })
            .catchError((Object error, StackTrace stackTrace) {
              // Simulates logging and absorbing error without stalling queue
            });
      }

      // Enqueue 3 tasks where the 2nd task throws an exception
      queueTask('event-1');
      queueTask('event-2', shouldFail: true);
      queueTask('event-3');

      // Await queue draining
      await eventQueue;

      // Verify event-1 and event-3 completed in order despite event-2 failure
      expect(processedEvents, equals(['event-1', 'event-3']));
    });

    test('event queue strictly preserves FIFO execution order', () async {
      final executionOrder = <int>[];
      Future<void> eventQueue = Future.value();

      void queueTask(int id, int delayMs) {
        eventQueue = eventQueue
            .then((_) async {
              await Future<void>.delayed(Duration(milliseconds: delayMs));
              executionOrder.add(id);
            })
            .catchError((_, __) {});
      }

      // Event 1 has longer simulated DB write than Event 2
      queueTask(1, 30);
      queueTask(2, 5);
      queueTask(3, 10);

      await eventQueue;

      // Must be 1, 2, 3 in arrival order, NOT 2, 3, 1 based on task duration
      expect(executionOrder, equals([1, 2, 3]));
    });
  });
}
