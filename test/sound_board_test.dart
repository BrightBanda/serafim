import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/platform/sound_board.dart';
import 'package:serafim/src/presentation/view/settings/sound_settings_page.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/sound_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeOutput implements SoundOutput {
  final loaded = <String>[];
  final played = <String>[];
  final previewed = <String>[];

  @override
  Future<void> load(SoundEvent event, SoundChoice choice) async =>
      loaded.add('${event.name}=${choice.encode()}');

  @override
  Future<void> play(SoundEvent event, double volume) async =>
      played.add('${event.name}@$volume');

  @override
  Future<void> preview(SoundChoice choice, double volume) async =>
      previewed.add(choice.encode());

  @override
  Future<Duration?> probe(String path) async => const Duration(seconds: 1);

  @override
  Future<void> dispose() async {}
}

void main() {
  group('choices', () {
    test('round-trip, and unknown ones are ignored', () {
      for (final c in [
        const SoundChoice.none(),
        const SoundChoice.builtIn('chime'),
        const SoundChoice.file('/x/y.mp3', name: 'My beep'),
      ]) {
        final back = SoundChoice.decode(c.encode())!;
        expect(back, c);
        expect(back.label, c.label);
      }
      expect(SoundChoice.decode('builtin:nope'), isNull);
      expect(SoundChoice.decode('???'), isNull);
      expect(const SoundChoice.file('/a', name: 'Beep').label, 'Beep');
    });

    test('the default received sound is the Serafim one', () {
      expect(
        SoundEvent.received.fallback,
        const SoundChoice.builtIn('serafim'),
      );
      expect(BuiltInSound.byId('serafim')!.asset, 'assets/sounds/serafim.wav');
    });
  });

  group('the board', () {
    late FakeOutput out;
    late DateTime now;
    late bool onScreen;
    late SoundBoard board;

    setUp(() async {
      out = FakeOutput();
      now = DateTime(2026, 11, 5, 12);
      onScreen = true;
      board = SoundBoard(out, clock: () => now, foreground: () => onScreen);
      await board.configure(enabled: true, volume: 0.5, choices: const {});
    });

    test('loads every event once, and only what changes later', () async {
      expect(out.loaded, hasLength(SoundEvent.values.length));
      out.loaded.clear();
      await board.configure(
        enabled: true,
        volume: 0.5,
        choices: {SoundEvent.sent: const SoundChoice.builtIn('pop')},
      );
      // "pop" isn't a built-in: decode would refuse it, but configure takes
      // what it is given; only the changed event is reloaded.
      expect(out.loaded, ['sent=builtin:pop']);
    });

    test('plays at the chosen volume', () {
      board.play(SoundEvent.received);
      expect(out.played, ['received@0.5']);
    });

    test('nothing when off, silent, muted or in the background', () async {
      await board.configure(enabled: false, volume: 0.5, choices: const {});
      board.play(SoundEvent.received);
      await board.configure(enabled: true, volume: 0, choices: const {});
      board.play(SoundEvent.received);
      await board.configure(
        enabled: true,
        volume: 0.5,
        choices: {SoundEvent.received: const SoundChoice.none()},
      );
      board.play(SoundEvent.received);
      await board.configure(enabled: true, volume: 0.5, choices: const {});
      onScreen = false;
      board.play(SoundEvent.received);
      expect(out.played, isEmpty);
    });

    test('a burst is one sound; the same message is never two', () {
      board.play(SoundEvent.received, key: 'm1');
      now = now.add(const Duration(milliseconds: 100));
      board.play(SoundEvent.received, key: 'm2');
      now = now.add(const Duration(seconds: 2));
      board.play(SoundEvent.received, key: 'm1'); // came again by push
      board.play(SoundEvent.received, key: 'm3');
      expect(out.played, ['received@0.5', 'received@0.5']);
    });

    test('typing waits a few seconds between ticks', () {
      board.play(SoundEvent.typing);
      now = now.add(const Duration(seconds: 2));
      board.play(SoundEvent.typing);
      now = now.add(const Duration(seconds: 3));
      board.play(SoundEvent.typing);
      expect(out.played, hasLength(2));
    });
  });

  group('settings', () {
    Future<ProviderContainer> container(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          soundOutputProvider.overrideWithValue(FakeOutput()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the old banner-sound switch carries over', () async {
      final c = await container({'settings.alertSound': false});
      expect(c.read(soundSettingsProvider).enabled, isFalse);
    });

    test('choices and volume are kept', () async {
      final c = await container({});
      final s = c.read(soundSettingsProvider.notifier);
      await s.setChoice(SoundEvent.typing, const SoundChoice.none());
      s.setVolume(0.3);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('sound.typing'), 'none');
      expect(p.getDouble('sound.volume'), 0.3);
      expect(
        c.read(soundSettingsProvider).choiceFor(SoundEvent.received),
        const SoundChoice.builtIn('serafim'),
      );
    });
  });

  testWidgets('the screen lists each event, and picking previews it', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final out = FakeOutput();
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          soundOutputProvider.overrideWithValue(out),
        ],
        child: const MaterialApp(home: SoundSettingsPage()),
      ),
    );
    await t.pumpAndSettle();
    for (final e in SoundEvent.values) {
      expect(find.text(e.label), findsOneWidget);
    }
    expect(find.text('Serafim'), findsOneWidget); // received
    await t.tap(find.byKey(const ValueKey('sound-notification')));
    await t.pumpAndSettle();
    await t.tap(find.text('Ping'));
    await t.pumpAndSettle();
    expect(p.getString('sound.notification'), 'builtin:ping');
    expect(out.previewed.last, 'builtin:ping');
    expect(find.text('Ping'), findsOneWidget);
  });
}
