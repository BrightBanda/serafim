import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/presentation/view/audio_library_page.dart';
import 'package:serafim/src/presentation/view/in_app_camera_page.dart';
import 'package:serafim/src/presentation/view/media_gallery_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/media_library_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/media_picker/media_widgets.dart';
import 'package:serafim/src/utils/media_picker/recent_media_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_media_library.dart';

Future<void> show(WidgetTester t, FakeLibrary library, Widget child) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [mediaLibraryProvider.overrideWithValue(library)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await t.pumpAndSettle();
}

/// Opens [page] from a button; returns what it pops through [result].
Future<void> open(
  WidgetTester t,
  FakeLibrary library,
  Widget page,
  void Function(Object?) result,
) async {
  await show(
    t,
    library,
    Builder(
      builder: (context) => TextButton(
        onPressed: () async => result(
          await Navigator.of(
            context,
          ).push<Object>(MaterialPageRoute(builder: (_) => page)),
        ),
        child: const Text('open'),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  group('the recent strip', () {
    Widget strip({
      ValueChanged<List<DeviceMedia>>? onSend,
      VoidCallback? onSeeAll,
    }) => RecentMediaStrip(
      filter: MediaFilter.visual,
      onSend: onSend ?? (_) {},
      onSeeAll: onSeeAll ?? () {},
    );

    testWidgets('never prompts by itself; asks only when tapped', (t) async {
      final library = FakeLibrary(
        items: fakeItems(3),
        current: MediaAccess.denied,
      );
      await show(t, library, strip());
      expect(library.requests, 0);
      expect(find.byKey(const ValueKey('media-allow')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('media-allow')));
      await t.pumpAndSettle();
      expect(library.requests, 1);
      expect(find.byKey(const ValueKey('recent-strip')), findsOneWidget);
      expect(find.byType(MediaThumb), findsNWidgets(3));
    });

    testWidgets('after a refusal it offers the settings', (t) async {
      final library = FakeLibrary(
        current: MediaAccess.denied,
        afterRequest: MediaAccess.denied,
      );
      await show(t, library, strip());
      await t.tap(find.byKey(const ValueKey('media-allow')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-settings')));
      expect(library.settingsOpened, 1);
    });

    testWidgets('selects in order, up to the limit, and sends them', (t) async {
      List<DeviceMedia>? sent;
      final library = FakeLibrary(items: fakeItems(6));
      await show(
        t,
        library,
        SizedBox(width: 800, child: strip(onSend: (s) => sent = s)),
      );
      Future<void> tap(String id) async {
        await t.tap(find.byKey(ValueKey('media-$id')));
        await t.pump();
      }

      for (final id in ['m2', 'm0', 'm1', 'm3']) {
        await tap(id);
      }
      await tap('m4');
      expect(
        find.text('You can send $maxMediaPick at a time.'),
        findsOneWidget,
      );
      await tap('m0'); // changed their mind
      await t.tap(find.byKey(const ValueKey('recent-send')));
      expect(sent!.map((m) => m.id), ['m2', 'm1', 'm3']);
    });

    testWidgets('only loads its share, and See all goes further', (t) async {
      var all = 0;
      final library = FakeLibrary(items: fakeItems(100));
      await show(t, library, strip(onSeeAll: () => all++));
      expect(library.pagesAsked, [0]);
      await t.tap(find.byKey(const ValueKey('recent-all')));
      expect(all, 1);
    });

    testWidgets('is simply absent where there is no library', (t) async {
      final library = FakeLibrary(current: MediaAccess.unavailable);
      await show(t, library, strip());
      expect(find.byKey(const ValueKey('media-allow')), findsNothing);
      expect(find.byKey(const ValueKey('recent-strip')), findsNothing);
    });
  });

  group('the gallery page', () {
    testWidgets('pops what was chosen', (t) async {
      Object? result;
      final library = FakeLibrary(items: fakeItems(4));
      await open(
        t,
        library,
        const MediaGalleryPage(filter: MediaFilter.visual),
        (r) => result = r,
      );
      expect(find.byKey(const ValueKey('gallery-send')), findsNothing);
      await t.tap(find.byKey(const ValueKey('media-m1')));
      await t.pump();
      expect(find.text('SEND 1'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('gallery-send')));
      await t.pumpAndSettle();
      expect((result! as List<DeviceMedia>).single.id, 'm1');
    });

    testWidgets('loads more as you scroll, not all at once', (t) async {
      final library = FakeLibrary(items: fakeItems(200));
      await open(
        t,
        library,
        const MediaGalleryPage(filter: MediaFilter.visual),
        (_) {},
      );
      expect(library.pagesAsked, [0]);
      await t.drag(find.byType(GridView), const Offset(0, -5000));
      await t.pumpAndSettle();
      expect(library.pagesAsked.length, greaterThan(1));
    });

    testWidgets('offers the system browser', (t) async {
      Object? result;
      await open(
        t,
        FakeLibrary(items: fakeItems(1)),
        const MediaGalleryPage(filter: MediaFilter.visual),
        (r) => result = r,
      );
      await t.tap(find.byKey(const ValueKey('gallery-browse')));
      await t.pumpAndSettle();
      expect(result, browseFiles);
    });

    testWidgets('with some photos shared, offers to share more', (t) async {
      final library = FakeLibrary(
        items: fakeItems(1),
        current: MediaAccess.limited,
      );
      await open(
        t,
        library,
        const MediaGalleryPage(filter: MediaFilter.visual),
        (_) {},
      );
      await t.tap(find.byKey(const ValueKey('gallery-select-more')));
      await t.pumpAndSettle();
      expect(library.selectMoreCalls, 1);
      expect(t.takeException(), isNull, reason: 'albums reload cleanly');
    });

    testWidgets('albums can be switched', (t) async {
      final library = FakeLibrary(
        items: fakeItems(2),
        albumNames: const ['Recent', 'Camera'],
      );
      await open(
        t,
        library,
        const MediaGalleryPage(filter: MediaFilter.visual),
        (_) {},
      );
      await t.tap(find.byKey(const ValueKey('gallery-album')));
      await t.pumpAndSettle();
      await t.tap(find.text('Camera').last);
      await t.pumpAndSettle();
      expect(library.pagesAsked, [0, 0]);
      expect(t.takeException(), isNull);
    });
  });

  group('the audio list', () {
    testWidgets('tapping one chooses it', (t) async {
      Object? result;
      await open(
        t,
        FakeLibrary(items: fakeItems(2, audio: true)),
        const AudioLibraryPage(),
        (r) => result = r,
      );
      expect(find.text('m0.mp3'), findsOneWidget);
      expect(find.text('1:05'), findsNWidgets(2));
      await t.tap(find.byKey(const ValueKey('audio-m1')));
      await t.pumpAndSettle();
      expect((result! as DeviceMedia).id, 'm1');
    });

    testWidgets('says so when there is none, and can browse', (t) async {
      Object? result;
      await open(t, FakeLibrary(), const AudioLibraryPage(), (r) => result = r);
      expect(find.text('No audio files found.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('audio-browse')));
      await t.pumpAndSettle();
      expect(result, browseFiles);
    });
  });

  testWidgets('a camera that cannot start offers the phone camera', (t) async {
    Object? result;
    await show(
      t,
      FakeLibrary(),
      Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await Navigator.of(context).push<Object>(
                MaterialPageRoute(builder: (_) => const InAppCameraPage()),
              ),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    // Finding out takes real time, with a spinner going meanwhile.
    final problem = find.byKey(const ValueKey('camera-problem'));
    for (var i = 0; i < 40 && problem.evaluate().isEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(problem, findsOneWidget);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const ValueKey('camera-use-phone')));
    await t.pumpAndSettle();
    expect(result, usePhoneCamera);
  });

  test('duration reads like a clock', () {
    expect(formatMediaDuration(const Duration(seconds: 7)), '0:07');
    expect(
      formatMediaDuration(const Duration(minutes: 3, seconds: 41)),
      '3:41',
    );
    expect(
      formatMediaDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  group('recovering a lost pick', () {
    Future<ProviderContainer> container(
      List<XFile> lost, {
      String account = 'me',
      int? asked,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentAccountIdProvider.overrideWithValue(account),
          lostPickSourceProvider.overrideWithValue(() async => lost),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    const target = PickTarget(
      account: 'me',
      recipientId: 'g1',
      contactName: 'Crew: the | best',
      groupId: 'g1',
      isGroup: true,
    );
    final photo = XFile('/x/a.jpg');

    test('the note survives being written down', () {
      final back = PickTarget.decode(target.encode())!;
      expect(back.contactName, target.contactName);
      expect(back.groupId, 'g1');
      expect(back.isGroup, isTrue);
      expect(back.username, isNull);
      expect(PickTarget.decode('rubbish'), isNull);
      expect(PickTarget.decode(null), isNull);
    });

    test('comes back to the chat it was for, once', () async {
      final c = await container([photo]);
      c.read(pickTargetStoreProvider).remember(target);
      final lost = await c.read(lostPickProvider.future);
      expect(lost!.target.recipientId, 'g1');
      expect(lost.files.single.path, photo.path);
      expect(c.read(pickTargetStoreProvider).current, isNull);
    });

    test('nothing back: nothing happens, and the note is gone', () async {
      final c = await container(const []);
      c.read(pickTargetStoreProvider).remember(target);
      expect(await c.read(lostPickProvider.future), isNull);
      expect(c.read(pickTargetStoreProvider).current, isNull);
    });

    test('a pick from another screen never lands in a chat', () async {
      final c = await container([photo]);
      expect(await c.read(lostPickProvider.future), isNull);
    });

    test("never shows in someone else's account", () async {
      final c = await container([photo], account: 'other');
      c.read(pickTargetStoreProvider).remember(target);
      expect(await c.read(lostPickProvider.future), isNull);
      expect(c.read(pickTargetStoreProvider).current, isNull);
    });
  });
}
