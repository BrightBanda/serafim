// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/data/services/video_trim_service.dart';
import 'package:serafim/src/presentation/view/video_trim_page.dart';
import 'package:serafim/src/providers/video_trim_providers.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A player that opens any file as a 60 s video and records where it was told
/// to seek.
class FakePlayer extends VideoPlayerPlatform {
  final seeks = <Duration>[];

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<int?> create(DataSource dataSource) async => 1;
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 60),
      size: const Size(1080, 1920),
    ),
  );
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      seeks.add(position);
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.expand();
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

class FakeTrimmer implements VideoTrimService {
  FakeTrimmer(this.out);

  final String out;
  final calls = <(Duration, Duration)>[];
  bool cancelled = false;
  Completer<String>? hold;

  @override
  bool get supported => true;

  @override
  Future<String> trim({
    required String path,
    required Duration start,
    required Duration end,
  }) {
    calls.add((start, end));
    return hold?.future ?? Future.value(out);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

void main() {
  late FakePlayer player;
  late Directory dir;
  late File trimmedFile;
  late PickedChatFile video;

  setUp(() {
    player = FakePlayer();
    VideoPlayerPlatform.instance = player;
    dir = Directory.systemTemp.createTempSync('trim_page_test');
    trimmedFile = File('${dir.path}/trim.mp4')
      ..writeAsBytesSync(List.filled(2048, 1));
    video = const PickedChatFile(
      path: '/dcim/holiday.mov',
      name: 'holiday.mov',
      size: 30 * 1024 * 1024,
      kind: ChatFileKind.video,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Opens the page the way chat does and returns what it pops with.
  Future<Future<PickedChatFile?>> open(
    WidgetTester tester,
    FakeTrimmer trimmer,
  ) async {
    late Future<PickedChatFile?> result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoTrimServiceProvider.overrideWithValue(trimmer)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = chooseVideoPart(context, video),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Future<void> dragStartHandle(WidgetTester tester, double fraction) async {
    final slider = tester.getRect(find.byKey(const ValueKey('trim-slider')));
    final width = slider.width - 48; // the track is inset by the thumb radius
    await tester.dragFrom(
      Offset(slider.left + 24, slider.center.dy),
      Offset(width * fraction, 0),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeping all of it sends the original, untouched', (t) async {
    final trimmer = FakeTrimmer(trimmedFile.path);
    final result = await open(t, trimmer);
    expect(find.text('SEND'), findsOneWidget);
    await t.tap(find.text('SEND'));
    await t.pumpAndSettle();
    expect((await result)?.path, video.path);
    expect(trimmer.calls, isEmpty);
  });

  testWidgets('moving a handle trims, and what comes back is the clip', (
    t,
  ) async {
    final trimmer = FakeTrimmer(trimmedFile.path);
    final result = await open(t, trimmer);
    await dragStartHandle(t, 0.5);

    expect(find.text('TRIM AND SEND'), findsOneWidget);
    expect(player.seeks, isNotEmpty); // the picture followed the handle

    await t.tap(find.text('TRIM AND SEND'));
    // Reading the new file's size is real disk I/O, outside the fake clock.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pumpAndSettle();

    final sent = (await result)!;
    expect(sent.path, trimmedFile.path);
    expect(sent.name, 'holiday.mp4');
    expect(sent.size, 2048);
    expect(sent.kind, ChatFileKind.video);
    expect(trimmer.calls.single.$1, greaterThan(const Duration(seconds: 20)));
    expect(trimmer.calls.single.$2, const Duration(seconds: 60));
    expect(
      sent.durationMs,
      trimmer.calls.single.$2.inMilliseconds -
          trimmer.calls.single.$1.inMilliseconds,
    );
  });

  testWidgets('closing sends nothing', (t) async {
    final trimmer = FakeTrimmer(trimmedFile.path);
    final result = await open(t, trimmer);
    await t.tap(find.byKey(const ValueKey('trim-close')));
    await t.pumpAndSettle();
    expect(await result, isNull);
    expect(trimmer.calls, isEmpty);
  });

  testWidgets('closing while it trims cancels the trim', (t) async {
    final trimmer = FakeTrimmer(trimmedFile.path)..hold = Completer<String>();
    final result = await open(t, trimmer);
    await dragStartHandle(t, 0.5);
    await t.tap(find.text('TRIM AND SEND'));
    await t.pump();
    expect(find.text('TRIMMING…'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('trim-close')));
    await t.pumpAndSettle();
    expect(trimmer.cancelled, isTrue);
    expect(await result, isNull);
  });

  testWidgets('a trim that fails says so and stays open', (t) async {
    final trimmer = FakeTrimmer(trimmedFile.path)..hold = Completer<String>();
    await open(t, trimmer);
    await dragStartHandle(t, 0.5);
    await t.tap(find.text('TRIM AND SEND'));
    await t.pump();
    trimmer.hold!.completeError(StateError('boom'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't trim that video."), findsOneWidget);
    expect(find.text('TRIM AND SEND'), findsOneWidget);
  });
}
