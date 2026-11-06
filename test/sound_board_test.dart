import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerInterruptedException;
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

/// Loading takes as long as [gate]; records what happens.
class _SlowOutput extends FakeOutput {
  _SlowOutput(this.gate, this.log);
  final Completer<void> gate;
  final List<String> log;
  @override
  Future<void> load(SoundEvent event, SoundChoice choice) => gate.future;
  @override
  Future<void> play(SoundEvent event, double volume) async =>
      log.add('play ${event.name}');
}

class _BrokenOutput extends FakeOutput {
  @override
  Future<void> preview(SoundChoice choice, double volume) async =>
      throw StateError('no audio');
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

    test('the typing pattern is never restarted while it plays', () {
      board.play(SoundEvent.typing);
      now = now.add(const Duration(milliseconds: 500));
      board.play(SoundEvent.typing);
      now = now.add(const Duration(milliseconds: 1500));
      board.play(SoundEvent.typing);
      expect(out.played, hasLength(2));
    });
  });

  group('playing safely', () {
    test(
      'a sound asked for while loading still plays, after its load',
      () async {
        final loading = Completer<void>();
        final log = <String>[];
        final out = _SlowOutput(loading, log);
        final board = SoundBoard(
          out,
          clock: () => DateTime(2026),
          foreground: () => true,
        );
        final configured = board.configure(
          enabled: true,
          volume: 0.5,
          choices: const {},
        );
        // Every event is known already, not just the one loading first.
        board.play(SoundEvent.typing);
        expect(log, contains('play typing'));
        loading.complete();
        await configured;
      },
    );

    test('a preview that fails does not throw', () async {
      final board = SoundBoard(_BrokenOutput(), foreground: () => true);
      await board.preview(const SoundChoice.builtIn('chime'));
    });

    test('steps never overlap, and go in order', () async {
      final steps = SoundSteps();
      final log = <String>[];
      final gate = Completer<void>();
      final a = steps.run(() async {
        log.add('a starts');
        await gate.future;
        log.add('a ends');
      });
      final b = steps.run(() async => log.add('b'));
      await Future<void>.delayed(Duration.zero);
      expect(log, ['a starts'], reason: 'b waits');
      gate.complete();
      await Future.wait([a, b]);
      expect(log, ['a starts', 'a ends', 'b']);
    });

    test('an interrupted step is not an error; a failed one does not block '
        'the next', () async {
      final steps = SoundSteps();
      await steps.run(() async => throw PlayerInterruptedException('gone'));
      await expectLater(
        steps.run(() async => throw StateError('broken')),
        throwsStateError,
      );
      var ran = false;
      await steps.run(() async => ran = true);
      expect(ran, isTrue);
    });
  });

  group('built-in sound files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sounds'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a changed sound is never played from an old copy', () async {
      final v1 = await builtInSoundFile(
        dir,
        'tick',
        Uint8List.fromList([1, 2]),
      );
      expect(v1.readAsBytesSync(), [1, 2]);
      final v2 = await builtInSoundFile(
        dir,
        'tick',
        Uint8List.fromList([3, 4]),
      );
      expect(v2.path, isNot(v1.path));
      expect(v2.readAsBytesSync(), [3, 4]);
      expect(v1.existsSync(), isFalse, reason: 'the old copy is removed');
    });

    test('the same sound is reused, and others are left alone', () async {
      final other = await builtInSoundFile(
        dir,
        'drop',
        Uint8List.fromList([9]),
      );
      final a = await builtInSoundFile(dir, 'tick', Uint8List.fromList([1]));
      final modified = a.lastModifiedSync();
      final b = await builtInSoundFile(dir, 'tick', Uint8List.fromList([1]));
      expect(b.path, a.path);
      expect(b.lastModifiedSync(), modified);
      expect(other.existsSync(), isTrue);
    });

    test('a damaged copy is replaced', () async {
      final a = await builtInSoundFile(dir, 'tick', Uint8List.fromList([1, 2]));
      a.writeAsBytesSync([1]);
      final b = await builtInSoundFile(dir, 'tick', Uint8List.fromList([1, 2]));
      expect(b.readAsBytesSync(), [1, 2]);
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
