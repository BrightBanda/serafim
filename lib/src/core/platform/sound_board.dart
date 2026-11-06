import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// The moments the app makes a sound for, while it is open.
enum SoundEvent {
  received(
    'Message received',
    'A new message arrives',
    Duration(milliseconds: 1200),
  ),
  sent(
    'Message sent',
    'The server has your message',
    Duration(milliseconds: 250),
  ),
  typing(
    'Typing',
    'Someone is typing in the chat you have open',
    Duration(milliseconds: 2000),
  ),
  notification(
    'Notifications',
    'Likes, comments, requests, invitations',
    Duration(seconds: 1),
  );

  const SoundEvent(this.label, this.when, this.minGap);

  final String label;

  /// When it plays, for the settings screen.
  final String when;

  /// Plays at most once per this long, so a burst (twenty messages arriving
  /// after a reconnect) is one sound, not twenty.
  final Duration minGap;

  SoundChoice get fallback => switch (this) {
    SoundEvent.received => const SoundChoice.builtIn('serafim'),
    SoundEvent.sent => const SoundChoice.builtIn('drop'),
    SoundEvent.typing => const SoundChoice.builtIn('tick'),
    SoundEvent.notification => const SoundChoice.builtIn('chime'),
  };
}

/// A sound that ships with the app (`assets/sounds/<id>.wav`: short, mono,
/// uncompressed, so they start instantly).
class BuiltInSound {
  const BuiltInSound(this.id, this.label);

  final String id;
  final String label;

  String get asset => 'assets/sounds/$id.wav';

  static const all = [
    BuiltInSound('serafim', 'Serafim'),
    BuiltInSound('drop', 'Drop'),
    BuiltInSound('chime', 'Chime'),
    BuiltInSound('ping', 'Ping'),
    BuiltInSound('bubble', 'Bubble'),
    BuiltInSound('swoosh', 'Swoosh'),
    BuiltInSound('tick', 'Tick'),
  ];

  static BuiltInSound? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// What plays for an event: nothing, a built-in sound, or a file the person
/// added (copied into the app's own storage).
class SoundChoice {
  const SoundChoice.none() : kind = 'none', value = '', name = '';
  const SoundChoice.builtIn(String id)
    : kind = 'builtin',
      value = id,
      name = '';
  const SoundChoice.file(String path, {this.name = ''})
    : kind = 'file',
      value = path;

  final String kind;
  final String value;

  /// A file's original name, to show.
  final String name;

  bool get isNone => kind == 'none';
  bool get isFile => kind == 'file';

  String get label => switch (kind) {
    'none' => 'None',
    'builtin' => BuiltInSound.byId(value)?.label ?? 'Default',
    _ => name.isEmpty ? 'Your sound' : name,
  };

  String encode() => kind == 'file'
      ? 'file:$value|$name'
      : kind == 'builtin'
      ? 'builtin:$value'
      : 'none';

  static SoundChoice? decode(String? raw) {
    if (raw == null) return null;
    if (raw == 'none') return const SoundChoice.none();
    if (raw.startsWith('builtin:')) {
      final id = raw.substring(8);
      return BuiltInSound.byId(id) == null ? null : SoundChoice.builtIn(id);
    }
    if (raw.startsWith('file:')) {
      final rest = raw.substring(5);
      final bar = rest.lastIndexOf('|');
      return bar < 0
          ? SoundChoice.file(rest)
          : SoundChoice.file(
              rest.substring(0, bar),
              name: rest.substring(bar + 1),
            );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SoundChoice && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Where the sound comes from: abstracted so the rules can be tested
/// without audio hardware.
abstract interface class SoundOutput {
  /// Gets [event]'s sound ready, so playing it later is instant.
  Future<void> load(SoundEvent event, SoundChoice choice);

  Future<void> play(SoundEvent event, double volume);

  /// Plays [choice] once (the settings screen's preview).
  Future<void> preview(SoundChoice choice, double volume);

  /// How long a file is, or null if it can't be played.
  Future<Duration?> probe(String path);

  Future<void> dispose();
}

/// Runs audio steps strictly one after another. A player cancels whatever it
/// is doing when asked to do something else (`PlayerInterruptedException`), so
/// nothing may overlap: a sound arriving while another is still loading waits
/// its turn. One step failing never stops the ones after it, and an interrupted
/// step (only possible as the player closes) is not an error.
class SoundSteps {
  Future<void> _last = Future.value();

  Future<void> run(Future<void> Function() step) {
    final next = _last.then((_) async {
      try {
        await step();
      } on PlayerInterruptedException catch (_) {}
    });
    _last = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// When everything asked for so far is done.
  Future<void> get idle => _last;
}

/// The file to play for a built-in sound. It is named after its contents, so a
/// new version of the app with a changed sound gets a new file, and older
/// copies are removed. (just_audio's own `setAsset` keeps the first copy it
/// ever made under the same name, for good.)
Future<File> builtInSoundFile(Directory dir, String id, Uint8List bytes) async {
  await dir.create(recursive: true);
  final file = File('${dir.path}/$id-${md5.convert(bytes)}.wav');
  if (await file.exists() && await file.length() == bytes.length) return file;
  // Written whole and then moved into place, so a half-written one is never
  // played.
  final partial = File('${file.path}.partial');
  await partial.writeAsBytes(bytes, flush: true);
  await partial.rename(file.path);
  await for (final old in dir.list()) {
    final name = old.uri.pathSegments.last;
    if (old.path != file.path && name.startsWith('$id-')) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }
  return file;
}

/// The real output: one small player per event, loaded ahead of time.
/// Sounds use Android's notification audio type, so they follow the
/// notification volume and silent/vibrate mode, and never pause the
/// person's music.
class JustAudioOutput implements SoundOutput {
  final _players = <SoundEvent, AudioPlayer>{};
  AudioPlayer? _previewer;
  final _steps = SoundSteps();
  bool _disposed = false;
  Directory? _soundDir;

  static Future<AudioPlayer> _player() async {
    final p = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    );
    if (Platform.isAndroid) {
      await p.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.notificationEvent,
        ),
      );
    }
    return p;
  }

  Future<Directory> _sounds() async {
    if (_soundDir case final dir?) return dir;
    final temp = await getTemporaryDirectory();
    // Earlier versions of the app played stale copies from here.
    try {
      await Directory(
        '${temp.path}/just_audio_cache/assets/assets/sounds',
      ).delete(recursive: true);
    } catch (_) {}
    return _soundDir = Directory('${temp.path}/serafim_sounds');
  }

  Future<void> _set(AudioPlayer p, SoundChoice choice) async {
    if (choice.isFile) {
      await p.setFilePath(choice.value);
      return;
    }
    final sound = BuiltInSound.byId(choice.value)!;
    final bytes = await rootBundle.load(sound.asset);
    final file = await builtInSoundFile(
      await _sounds(),
      sound.id,
      bytes.buffer.asUint8List(),
    );
    await p.setFilePath(file.path);
  }

  /// Starts [p] without waiting for the sound to finish.
  static void _start(AudioPlayer p) {
    unawaited(
      p.play().catchError((Object e) {
        if (e is! PlayerInterruptedException && kDebugMode) {
          // ignore: avoid_print
          print('[sound] could not play: $e');
        }
      }),
    );
  }

  @override
  Future<void> load(SoundEvent event, SoundChoice choice) =>
      _steps.run(() async {
        if (_disposed) return;
        if (choice.isNone) {
          await _players.remove(event)?.dispose();
          return;
        }
        final p = _players[event] ??= await _player();
        await _set(p, choice);
      });

  @override
  Future<void> play(SoundEvent event, double volume) => _steps.run(() async {
    final p = _players[event];
    if (p == null || _disposed) return;
    await p.setVolume(volume);
    await p.seek(Duration.zero);
    _start(p);
  });

  @override
  Future<void> preview(SoundChoice choice, double volume) =>
      _steps.run(() async {
        if (choice.isNone || _disposed) return;
        final p = _previewer ??= await _player();
        await p.stop();
        await _set(p, choice);
        await p.setVolume(volume);
        _start(p);
      });

  @override
  Future<Duration?> probe(String path) async {
    final p = AudioPlayer(
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    );
    try {
      return await p.setFilePath(path);
    } catch (_) {
      return null;
    } finally {
      await p.dispose();
    }
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _steps.run(() async {
      for (final p in _players.values) {
        await p.dispose();
      }
      _players.clear();
      await _previewer?.dispose();
    });
  }
}

/// No sound: for tests, and platforms without an audio player (desktop).
class SilentOutput implements SoundOutput {
  const SilentOutput();
  @override
  Future<void> load(SoundEvent event, SoundChoice choice) async {}
  @override
  Future<void> play(SoundEvent event, double volume) async {}
  @override
  Future<void> preview(SoundChoice choice, double volume) async {}
  @override
  Future<Duration?> probe(String path) async => null;
  @override
  Future<void> dispose() async {}
}

/// Whether this build can play the app's sounds: Android and iOS, not in
/// tests.
bool get soundsSupported =>
    (Platform.isAndroid || Platform.isIOS) &&
    !Platform.environment.containsKey('FLUTTER_TEST');

/// Plays the app's sounds, by the person's settings. Plays nothing while the
/// app isn't on screen (the phone's own notification sound is for that),
/// nothing twice for the same thing ([key]: a message arriving by socket
/// and by push), and nothing more often than each event's [SoundEvent.minGap].
class SoundBoard {
  SoundBoard(
    this._output, {
    DateTime Function()? clock,
    bool Function()? foreground,
  }) : _clock = clock ?? DateTime.now,
       _foreground = foreground ?? _appOnScreen;

  final SoundOutput _output;
  final DateTime Function() _clock;
  final bool Function() _foreground;

  bool enabled = true;
  double volume = 0.8;
  final _choices = <SoundEvent, SoundChoice>{};
  final _last = <SoundEvent, DateTime>{};
  final _keys = <String>[];

  static bool _appOnScreen() {
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      // No app running (a background isolate, a plain test): nothing plays.
      return false;
    }
  }

  /// Applies settings: loads any sound that changed.
  Future<void> configure({
    required bool enabled,
    required double volume,
    required Map<SoundEvent, SoundChoice> choices,
  }) async {
    this.enabled = enabled;
    this.volume = volume;
    // All known at once, so a sound asked for while these load still plays
    // (its turn comes after its loading).
    final changed = <SoundEvent, SoundChoice>{};
    for (final event in SoundEvent.values) {
      final choice = choices[event] ?? event.fallback;
      if (_choices[event] == choice) continue;
      _choices[event] = choice;
      changed[event] = choice;
    }
    for (final MapEntry(key: event, value: choice) in changed.entries) {
      try {
        await _output.load(event, choice);
      } catch (e) {
        _log('could not load ${event.name}: $e');
      }
    }
  }

  /// Plays [event]'s sound, if it should. Never throws.
  void play(SoundEvent event, {String? key}) {
    if (!enabled || volume <= 0 || !_foreground()) return;
    final choice = _choices[event];
    if (choice == null || choice.isNone) return;
    if (key != null) {
      final k = '${event.name}:$key';
      if (_keys.contains(k)) return;
      _keys.add(k);
      if (_keys.length > 100) _keys.removeAt(0);
    }
    final now = _clock();
    final last = _last[event];
    if (last != null && now.difference(last) < event.minGap) return;
    _last[event] = now;
    _output
        .play(event, volume)
        .catchError((Object e) => _log('play ${event.name}: $e'));
  }

  /// Plays [choice] once, for the settings screen. Never throws.
  Future<void> preview(SoundChoice choice) async {
    try {
      await _output.preview(choice, volume <= 0 ? 0.8 : volume);
    } catch (e) {
      _log('could not preview: $e');
    }
  }

  Future<Duration?> probe(String path) => _output.probe(path);

  Future<void> dispose() => _output.dispose();

  void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[sound] $message');
    }
  }
}
