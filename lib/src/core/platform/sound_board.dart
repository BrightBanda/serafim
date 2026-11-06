import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:just_audio/just_audio.dart';

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

/// The real output: one small player per event, loaded ahead of time.
/// Sounds use Android's notification audio type, so they follow the
/// notification volume and silent/vibrate mode, and never pause the
/// person's music.
class JustAudioOutput implements SoundOutput {
  final _players = <SoundEvent, AudioPlayer>{};
  AudioPlayer? _previewer;

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

  static Future<void> _set(AudioPlayer p, SoundChoice choice) async {
    if (choice.isFile) {
      await p.setFilePath(choice.value);
    } else {
      await p.setAsset(BuiltInSound.byId(choice.value)!.asset);
    }
  }

  @override
  Future<void> load(SoundEvent event, SoundChoice choice) async {
    if (choice.isNone) {
      await _players.remove(event)?.dispose();
      return;
    }
    final p = _players[event] ??= await _player();
    await _set(p, choice);
  }

  @override
  Future<void> play(SoundEvent event, double volume) async {
    final p = _players[event];
    if (p == null) return;
    await p.setVolume(volume);
    await p.seek(Duration.zero);
    unawaited(p.play());
  }

  @override
  Future<void> preview(SoundChoice choice, double volume) async {
    if (choice.isNone) return;
    final p = _previewer ??= await _player();
    await p.stop();
    await _set(p, choice);
    await p.setVolume(volume);
    unawaited(p.play());
  }

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
  Future<void> dispose() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
    await _previewer?.dispose();
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
    for (final event in SoundEvent.values) {
      final choice = choices[event] ?? event.fallback;
      if (_choices[event] == choice) continue;
      _choices[event] = choice;
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

  Future<void> preview(SoundChoice choice) =>
      _output.preview(choice, volume <= 0 ? 0.8 : volume);

  Future<Duration?> probe(String path) => _output.probe(path);

  Future<void> dispose() => _output.dispose();

  void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[sound] $message');
    }
  }
}
