import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:serafim/src/data/services/media_service.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/utils/voice/voice_math.dart';

final mediaServiceProvider = Provider<MediaService>(
  (ref) => MediaService(ref.watch(apiDioProvider)),
);

// ---------------------------------------------------------------- recording

/// The microphone, behind an interface so the recording logic can be tested.
abstract class VoiceRecorderEngine {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
  Future<void> cancel();

  /// Levels in dBFS while recording.
  Stream<double> levels();

  /// True when the platform paused the recording itself (a phone call, another
  /// app taking audio focus).
  Stream<bool> pausedByPlatform();
}

class RecordEngine implements VoiceRecorderEngine {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      // AAC in an .m4a: small, and plays everywhere.
      encoder: AudioEncoder.aacLc,
      bitRate: 32000,
      sampleRate: 22050,
      numChannels: 1,
      // A call or another app taking the mic pauses the recording (it is not
      // lost); the user resumes or sends it.
      audioInterruption: AudioInterruptionMode.pause,
    ),
    path: path,
  );

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Stream<double> levels() => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((a) => a.current);

  @override
  Stream<bool> pausedByPlatform() =>
      _recorder.onStateChanged().map((s) => s == RecordState.pause);
}

final voiceRecorderEngineProvider = Provider<VoiceRecorderEngine>(
  (ref) => RecordEngine(),
);

/// A finished recording, ready to send.
class RecordedVoice {
  const RecordedVoice({
    required this.path,
    required this.durationMs,
    required this.waveform,
  });

  final String path;
  final int durationMs;
  final List<int> waveform;
}

enum RecordingPhase { idle, starting, recording, paused }

class VoiceRecordingState {
  const VoiceRecordingState({
    this.phase = RecordingPhase.idle,
    this.locked = false,
    this.elapsed = Duration.zero,
    this.level = 0,
  });

  final RecordingPhase phase;

  /// Hands-free: the finger was slid up, so letting go doesn't send.
  final bool locked;
  final Duration elapsed;

  /// Latest loudness, 0–31, for the live indicator.
  final int level;

  bool get active => phase != RecordingPhase.idle;

  VoiceRecordingState copyWith({
    RecordingPhase? phase,
    bool? locked,
    Duration? elapsed,
    int? level,
  }) => VoiceRecordingState(
    phase: phase ?? this.phase,
    locked: locked ?? this.locked,
    elapsed: elapsed ?? this.elapsed,
    level: level ?? this.level,
  );
}

/// Why recording could not start.
enum RecordStartResult { started, denied, failed, busy }

/// Records one voice note at a time: hold to record, slide to lock or cancel,
/// a 5-minute limit, and pausing (never losing) on interruptions. Reaching
/// the limit pauses the recording too: nothing is sent or thrown away until
/// the person chooses.
class VoiceRecorderController extends Notifier<VoiceRecordingState> {
  VoiceRecorderEngine get _engine => ref.read(voiceRecorderEngineProvider);

  final Stopwatch _clock = Stopwatch();
  final List<double> _levels = [];
  Timer? _ticker;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<bool>? _pauseSub;
  String? _path;

  /// Called when the recording reaches the 5-minute limit and is paused.
  void Function()? _onLimit;

  @override
  VoiceRecordingState build() {
    ref.onDispose(_teardown);
    return const VoiceRecordingState();
  }

  /// The longest recording (5 minutes). Shortened in tests.
  static Duration limit = maxVoiceDuration;

  /// Directory for in-progress recordings. Replaced in tests.
  static Future<String> Function() tempDir = () async =>
      (await getTemporaryDirectory()).path;

  /// Whether the recording has reached [limit] (it can't be resumed).
  bool get atLimit => _clock.elapsed >= limit;

  Future<RecordStartResult> start({void Function()? onLimit}) async {
    if (state.active) return RecordStartResult.busy;
    state = state.copyWith(phase: RecordingPhase.starting);
    try {
      if (!await _engine.hasPermission()) {
        state = const VoiceRecordingState();
        return RecordStartResult.denied;
      }
      // The finger may have been lifted (cancelled) while we asked.
      if (state.phase != RecordingPhase.starting) {
        return RecordStartResult.failed;
      }
      // A voice note that is playing would end up in the recording.
      await ref.read(voicePlayerProvider.notifier).stop();

      final dir = await tempDir();
      _path = '$dir/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      _levels.clear();
      await _engine.start(_path!);
      if (state.phase != RecordingPhase.starting) {
        // Cancelled while the microphone was starting.
        await _engine.cancel();
        return RecordStartResult.failed;
      }
      _onLimit = onLimit;
      _clock
        ..reset()
        ..start();
      _levelSub = _engine.levels().listen((db) {
        _levels.add(db);
        state = state.copyWith(level: waveformFromLevels([db], bars: 1).first);
      });
      _pauseSub = _engine.pausedByPlatform().listen((paused) {
        if (paused && state.phase == RecordingPhase.recording) {
          // Interrupted: keep what we have, hands-free, until they decide.
          _clock.stop();
          state = state.copyWith(phase: RecordingPhase.paused, locked: true);
        }
      });
      _ticker = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _tick(),
      );
      state = state.copyWith(phase: RecordingPhase.recording);
      return RecordStartResult.started;
    } catch (_) {
      await _teardown();
      state = const VoiceRecordingState();
      return RecordStartResult.failed;
    }
  }

  void _tick() {
    final elapsed = _clock.elapsed;
    state = state.copyWith(elapsed: elapsed);
    if (elapsed >= limit && state.phase == RecordingPhase.recording) {
      pause().then((_) => _onLimit?.call());
    }
  }

  void lock() {
    if (state.phase == RecordingPhase.recording) {
      state = state.copyWith(locked: true);
    }
  }

  Future<void> pause() async {
    if (state.phase != RecordingPhase.recording) return;
    try {
      await _engine.pause();
    } catch (_) {}
    _clock.stop();
    state = state.copyWith(phase: RecordingPhase.paused, locked: true);
  }

  Future<void> resume() async {
    if (state.phase != RecordingPhase.paused || atLimit) return;
    try {
      await _engine.resume();
      _clock.start();
      state = state.copyWith(phase: RecordingPhase.recording);
    } catch (_) {}
  }

  /// The app went to the background, or the finger's gesture was taken away
  /// (e.g. by a system dialog): keep the recording, paused and hands-free.
  Future<void> interrupt() async {
    if (!ref.mounted) return;
    if (state.phase == RecordingPhase.recording) await pause();
    if (state.phase == RecordingPhase.starting) await cancel();
  }

  /// Throws the recording away.
  Future<void> cancel() async {
    // Called from a closing chat, possibly after the app state is gone.
    if (!ref.mounted) return;
    final wasStarting = state.phase == RecordingPhase.starting;
    state = const VoiceRecordingState();
    if (wasStarting) return; // start() notices and gives up.
    try {
      await _engine.cancel();
    } catch (_) {}
    await _teardown();
    final path = _path;
    _path = null;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Stops and returns the recording, or null if it was too short to send.
  Future<RecordedVoice?> finish() async {
    if (state.phase != RecordingPhase.recording &&
        state.phase != RecordingPhase.paused) {
      return null;
    }
    final elapsed = _clock.elapsed;
    String? path;
    try {
      path = await _engine.stop();
    } catch (_) {}
    path ??= _path;
    final levels = List<double>.of(_levels);
    await _teardown();
    _path = null;
    state = const VoiceRecordingState();

    if (path == null || elapsed < minVoiceDuration) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      return null;
    }
    final capped = elapsed > limit ? limit : elapsed;
    return RecordedVoice(
      path: path,
      durationMs: capped.inMilliseconds,
      waveform: waveformFromLevels(levels),
    );
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    await _levelSub?.cancel();
    await _pauseSub?.cancel();
    _levelSub = null;
    _pauseSub = null;
  }
}

final voiceRecorderProvider =
    NotifierProvider<VoiceRecorderController, VoiceRecordingState>(
      VoiceRecorderController.new,
    );

// ----------------------------------------------------------------- playback

/// Plays audio files, behind an interface so playback logic can be tested.
abstract class VoicePlaybackEngine {
  Future<Duration?> load(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Stream<Duration> get positions;

  /// Fires when the current file plays to the end.
  Stream<void> get completed;

  /// Fires when playback stops by itself (interruption, headphones unplugged).
  Stream<bool> get playing;
}

class JustAudioEngine implements VoicePlaybackEngine {
  JustAudioEngine() {
    if (!kIsWeb) {
      // Speech settings: ducks other audio, pauses on calls and when
      // headphones are unplugged (just_audio follows the session).
      AudioSession.instance.then(
        (s) => s.configure(const AudioSessionConfiguration.speech()),
      );
    }
  }

  final AudioPlayer _player = AudioPlayer();

  @override
  Future<Duration?> load(String path) => _player.setFilePath(path);

  @override
  Future<void> play() async {
    // play() only completes when playback ends; don't wait for that.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Stream<Duration> get positions => _player.positionStream;

  @override
  Stream<void> get completed => _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<bool> get playing => _player.playingStream;
}

final voicePlaybackEngineProvider = Provider<VoicePlaybackEngine>(
  (ref) => JustAudioEngine(),
);

class VoicePlaybackState {
  const VoicePlaybackState({
    this.messageId,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
  });

  /// The voice note loaded in the player (playing or paused), if any.
  final String? messageId;
  final bool playing;
  final Duration position;
  final Duration duration;

  /// 1×, 1.5× or 2×; kept between voice notes.
  final double speed;

  VoicePlaybackState copyWith({
    String? messageId,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? speed,
    bool clearMessage = false,
  }) => VoicePlaybackState(
    messageId: clearMessage ? null : (messageId ?? this.messageId),
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
  );
}

const voiceSpeeds = [1.0, 1.5, 2.0];

/// One player for every voice note, so starting one stops any other.
class VoicePlayerController extends Notifier<VoicePlaybackState> {
  VoicePlaybackEngine? _engineRef;

  // Kept once created: the dispose callback can't read providers.
  VoicePlaybackEngine get _engine {
    final VoicePlaybackEngine engine =
        _engineRef ?? ref.read(voicePlaybackEngineProvider);
    _engineRef = engine;
    return engine;
  }

  final List<StreamSubscription<Object?>> _subs = [];
  bool _listening = false;

  @override
  VoicePlaybackState build() {
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      // Only if something was ever played (don't create a player to stop it).
      _engineRef?.stop();
    });
    return const VoicePlaybackState();
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _subs
      ..add(
        _engine.positions.listen((p) {
          if (state.messageId != null) state = state.copyWith(position: p);
        }),
      )
      ..add(
        _engine.completed.listen((_) {
          _engine.pause();
          _engine.seek(Duration.zero);
          state = state.copyWith(playing: false, position: Duration.zero);
        }),
      )
      ..add(
        _engine.playing.listen((p) {
          if (state.messageId != null && p != state.playing) {
            state = state.copyWith(playing: p);
          }
        }),
      );
  }

  /// Plays [messageId] from [path], or pauses it if it is the one playing.
  Future<void> toggle(String messageId, String path, {int? durationMs}) async {
    _listen();
    if (state.messageId == messageId) {
      if (state.playing) {
        await _engine.pause();
        state = state.copyWith(playing: false);
      } else {
        await _engine.play();
        state = state.copyWith(playing: true);
      }
      return;
    }
    // A different note: whatever was playing stops first.
    await _engine.stop();
    final duration = await _engine.load(path);
    await _engine.setSpeed(state.speed);
    state = state.copyWith(
      messageId: messageId,
      position: Duration.zero,
      duration: duration ?? Duration(milliseconds: durationMs ?? 0),
      playing: true,
    );
    await _engine.play();
  }

  Future<void> seek(String messageId, double fraction) async {
    if (state.messageId != messageId) return;
    final to = state.duration * fraction.clamp(0.0, 1.0);
    await _engine.seek(to);
    state = state.copyWith(position: to);
  }

  /// 1× → 1.5× → 2× → 1×.
  Future<void> cycleSpeed() async {
    final i = voiceSpeeds.indexOf(state.speed);
    final next = voiceSpeeds[(i + 1) % voiceSpeeds.length];
    state = state.copyWith(speed: next);
    if (state.messageId != null) await _engine.setSpeed(next);
  }

  Future<void> stop() async {
    if (!ref.mounted || state.messageId == null) return;
    await _engine.stop();
    state = state.copyWith(
      clearMessage: true,
      playing: false,
      position: Duration.zero,
    );
  }
}

final voicePlayerProvider =
    NotifierProvider<VoicePlayerController, VoicePlaybackState>(
      VoicePlayerController.new,
    );

/// Upload progress (0–1) of voice notes being sent, by message id.
class VoiceUploadProgress extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  void set(String messageId, double progress) =>
      state = {...state, messageId: progress};

  void clear(String messageId) => state = {...state}..remove(messageId);
}

final voiceUploadProgressProvider =
    NotifierProvider<VoiceUploadProgress, Map<String, double>>(
      VoiceUploadProgress.new,
    );
