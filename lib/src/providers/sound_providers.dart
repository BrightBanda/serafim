import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/core/platform/sound_board.dart';
import 'package:serafim/src/providers/settings_providers.dart';

/// The app's sound settings: on or off, how loud, and what plays for each
/// event.
class SoundSettings {
  const SoundSettings({
    this.enabled = true,
    this.volume = 0.8,
    this.choices = const {},
  });

  final bool enabled;
  final double volume;
  final Map<SoundEvent, SoundChoice> choices;

  SoundChoice choiceFor(SoundEvent event) => choices[event] ?? event.fallback;

  SoundSettings copyWith({
    bool? enabled,
    double? volume,
    Map<SoundEvent, SoundChoice>? choices,
  }) => SoundSettings(
    enabled: enabled ?? this.enabled,
    volume: volume ?? this.volume,
    choices: choices ?? this.choices,
  );
}

/// Your own sounds: at most this big and this long.
const customSoundMaxBytes = 2 * 1024 * 1024;
const customSoundMaxLength = Duration(seconds: 10);

class SoundSettingsController extends Notifier<SoundSettings> {
  static const _enabled = 'sound.enabled';
  static const _volume = 'sound.volume';
  // Before this screen existed, one switch turned the banner sound on or
  // off; that choice carries over.
  static const _oldSwitch = 'settings.alertSound';

  static String _key(SoundEvent e) => 'sound.${e.name}';

  @override
  SoundSettings build() {
    final p = ref.watch(sharedPreferencesProvider);
    return SoundSettings(
      enabled: p.getBool(_enabled) ?? p.getBool(_oldSwitch) ?? true,
      volume: (p.getDouble(_volume) ?? 0.8).clamp(0.0, 1.0),
      choices: {
        for (final e in SoundEvent.values)
          if (SoundChoice.decode(p.getString(_key(e))) case final c?) e: c,
      },
    );
  }

  void setEnabled(bool on) {
    state = state.copyWith(enabled: on);
    ref.read(sharedPreferencesProvider).setBool(_enabled, on);
  }

  void setVolume(double v) {
    state = state.copyWith(volume: v);
    ref.read(sharedPreferencesProvider).setDouble(_volume, v);
  }

  Future<void> setChoice(SoundEvent event, SoundChoice choice) async {
    final before = state.choiceFor(event);
    state = state.copyWith(choices: {...state.choices, event: choice});
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key(event), choice.encode());
    // A file nothing uses any more is removed.
    if (before.isFile &&
        before != choice &&
        !SoundEvent.values.any((e) => state.choiceFor(e) == before)) {
      try {
        await File(before.value).delete();
      } catch (_) {}
    }
  }

  /// Lets the person pick a sound from their phone for [event]. Returns why
  /// it can't be used, or null once it is set (or they backed out).
  Future<String?> importSound(SoundEvent event) async {
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    final path = picked?.files.single.path;
    if (picked == null || path == null) return null;
    final file = File(path);
    if (await file.length() > customSoundMaxBytes) {
      return 'That sound is too big. Pick one under 2 MB.';
    }
    final length = await ref.read(soundBoardProvider).probe(path);
    if (length == null) return "That file can't be played.";
    if (length > customSoundMaxLength) {
      return 'Pick a sound up to 10 seconds long.';
    }
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/sounds',
    );
    await dir.create(recursive: true);
    final name = picked.files.single.name;
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
    final copy = await file.copy(
      '${dir.path}/${event.name}-${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    final label = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    await setChoice(event, SoundChoice.file(copy.path, name: label));
    return null;
  }
}

final soundSettingsProvider =
    NotifierProvider<SoundSettingsController, SoundSettings>(
      SoundSettingsController.new,
    );

/// Where sounds come out. Tests swap in a silent one.
final soundOutputProvider = Provider<SoundOutput>((ref) {
  final SoundOutput output = soundsSupported
      ? JustAudioOutput()
      : const SilentOutput();
  ref.onDispose(output.dispose);
  return output;
});

/// The app's sound board, kept in step with the settings (each sound is
/// loaded once, ahead of time).
final soundBoardProvider = Provider<SoundBoard>((ref) {
  final board = SoundBoard(ref.watch(soundOutputProvider));
  ref.listen<SoundSettings>(soundSettingsProvider, (_, s) {
    unawaited(
      board.configure(enabled: s.enabled, volume: s.volume, choices: s.choices),
    );
  }, fireImmediately: true);
  return board;
});
