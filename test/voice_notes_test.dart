import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/services/chat_media_store.dart';
import 'package:serafim/src/data/services/media_service.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/voice/voice_math.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ------------------------------------------------------------------ fakes ---

class FakeMic implements VoiceRecorderEngine {
  bool allow = true;
  final levelCtl = StreamController<double>.broadcast();
  final pauseCtl = StreamController<bool>.broadcast();
  final calls = <String>[];
  String? path;

  @override
  Future<bool> hasPermission() async => allow;
  @override
  Future<void> start(String path) async {
    calls.add('start');
    this.path = path;
    File(path).writeAsBytesSync([1, 2, 3]);
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<String?> stop() async {
    calls.add('stop');
    return path;
  }

  @override
  Future<void> cancel() async => calls.add('cancel');
  @override
  Stream<double> levels() => levelCtl.stream;
  @override
  Stream<bool> pausedByPlatform() => pauseCtl.stream;
}

class FakeSpeaker implements VoicePlaybackEngine {
  final calls = <String>[];
  final pos = StreamController<Duration>.broadcast();
  final done = StreamController<void>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();

  @override
  Future<Duration?> load(String path) async {
    calls.add('load $path');
    return const Duration(seconds: 10);
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek ${position.inSeconds}');
  @override
  Future<void> setSpeed(double speed) async => calls.add('speed $speed');
  @override
  Stream<Duration> get positions => pos.stream;
  @override
  Stream<void> get completed => done.stream;
  @override
  Stream<bool> get playing => playingCtl.stream;
}

class FakeMedia extends MediaService {
  FakeMedia() : super(Dio());
  final uploads = <String>[];
  int failuresLeft = 0;

  @override
  Future<VoiceUpload> uploadVoice({
    required Uint8List bytes,
    required String clientId,
    required int durationMs,
    required List<int> waveform,
    String? recipientId,
    String? groupId,
    void Function(double progress)? onProgress,
  }) async {
    uploads.add(clientId);
    onProgress?.call(0.5);
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const ApiException("Can't reach the server.");
    }
    // Like the server: the same client id is the same upload.
    return VoiceUpload(
      id: 'media-$clientId',
      durationMs: durationMs,
      waveform: waveform,
    );
  }

  @override
  Future<Uint8List> download(String mediaId) async => Uint8List.fromList([9]);
}

class FakeSocket extends WebSocketService {
  final sent = <Map<String, dynamic>>[];
  @override
  bool sendMessage(Map<String, dynamic> payload) {
    sent.add(payload);
    return true;
  }
}

class TempStore extends ChatMediaStore {
  TempStore(this.dir);
  final Directory dir;

  @override
  Future<String> save(
    String messageId,
    Uint8List bytes, {
    String? extension,
  }) async {
    final f = File('${dir.path}/$messageId.${extension ?? 'bin'}');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  @override
  Future<String> adoptRecording(String messageId, String tempPath) async =>
      (await File(tempPath).rename('${dir.path}/$messageId.m4a')).path;
}

void main() {
  // ------------------------------------------------------------- helpers ---
  group('helpers', () {
    test('waveform: quiet is low, loud is high, always the bar count', () {
      final w = waveformFromLevels([-60, -60, -25, 0], bars: 4);
      expect(w, [0, 0, 16, 31]);
      expect(waveformFromLevels([]).length, waveformBars);
      expect(waveformFromLevels(List.filled(500, -10.0)).length, waveformBars);
    });

    test('durations', () {
      expect(formatVoiceDuration(const Duration(seconds: 7)), '0:07');
      expect(
        formatVoiceDuration(const Duration(minutes: 4, seconds: 59)),
        '4:59',
      );
    });

    test('slide left cancels, slide up locks', () {
      expect(recordGestureFor(const Offset(-100, 0)), RecordGesture.cancel);
      expect(recordGestureFor(const Offset(0, -80)), RecordGesture.lock);
      expect(recordGestureFor(const Offset(-20, -20)), RecordGesture.none);
    });
  });

  // ------------------------------------------------------------ recorder ---
  group('recording', () {
    late Directory tmp;
    late FakeMic mic;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('voice');
      VoiceRecorderController.tempDir = () async => tmp.path;
      mic = FakeMic();
      c = ProviderContainer(
        overrides: [
          voiceRecorderEngineProvider.overrideWithValue(mic),
          voicePlaybackEngineProvider.overrideWithValue(FakeSpeaker()),
        ],
      );
    });
    tearDown(() {
      c.dispose();
      VoiceRecorderController.limit = maxVoiceDuration;
      tmp.deleteSync(recursive: true);
    });

    VoiceRecorderController rec() => c.read(voiceRecorderProvider.notifier);

    test('permission denied is reported, nothing records', () async {
      mic.allow = false;
      expect(await rec().start(), RecordStartResult.denied);
      expect(c.read(voiceRecorderProvider).active, isFalse);
      expect(mic.calls, isEmpty);
    });

    test('hold, release: a recording with a waveform', () async {
      expect(await rec().start(), RecordStartResult.started);
      mic.levelCtl
        ..add(-40)
        ..add(-5);
      await Future<void>.delayed(
        minVoiceDuration + const Duration(milliseconds: 50),
      );
      final voice = await rec().finish();
      expect(voice, isNotNull);
      expect(
        voice!.durationMs,
        greaterThanOrEqualTo(minVoiceDuration.inMilliseconds),
      );
      expect(voice.waveform.length, waveformBars);
      expect(voice.waveform.reduce((a, b) => a > b ? a : b), greaterThan(20));
      expect(c.read(voiceRecorderProvider).active, isFalse);
    });

    test('a quick tap is not a message', () async {
      await rec().start();
      expect(await rec().finish(), isNull);
    });

    test('a call or lost audio focus pauses and keeps the recording', () async {
      await rec().start();
      mic.pauseCtl.add(true);
      await Future<void>.delayed(Duration.zero);
      final s = c.read(voiceRecorderProvider);
      expect(s.phase, RecordingPhase.paused);
      expect(s.locked, isTrue, reason: 'stays hands-free so it is not lost');
      await rec().resume();
      expect(c.read(voiceRecorderProvider).phase, RecordingPhase.recording);
    });

    test('backgrounding pauses instead of throwing it away', () async {
      await rec().start();
      await rec().interrupt();
      expect(c.read(voiceRecorderProvider).phase, RecordingPhase.paused);
      expect(mic.calls, contains('pause'));
      expect(mic.calls, isNot(contains('cancel')));
    });

    test('slide to cancel discards the file', () async {
      await rec().start();
      final path = mic.path!;
      await rec().cancel();
      expect(File(path).existsSync(), isFalse);
      expect(c.read(voiceRecorderProvider).active, isFalse);
    });

    test('the length limit stops and sends it', () async {
      VoiceRecorderController.limit = const Duration(milliseconds: 900);
      final sent = Completer<RecordedVoice>();
      await rec().start(onLimit: sent.complete);
      final voice = await sent.future.timeout(const Duration(seconds: 3));
      expect(voice.durationMs, lessThanOrEqualTo(900));
      expect(c.read(voiceRecorderProvider).active, isFalse);
    });
  });

  // ------------------------------------------------------------ playback ---
  group('playback', () {
    test('only one voice note plays at a time; speed cycles', () async {
      final speaker = FakeSpeaker();
      final c = ProviderContainer(
        overrides: [voicePlaybackEngineProvider.overrideWithValue(speaker)],
      );
      addTearDown(c.dispose);
      final p = c.read(voicePlayerProvider.notifier);

      await p.toggle('a', '/a.m4a');
      expect(c.read(voicePlayerProvider).messageId, 'a');
      expect(c.read(voicePlayerProvider).playing, isTrue);

      speaker.calls.clear();
      await p.toggle('b', '/b.m4a');
      expect(speaker.calls.first, 'stop', reason: 'a stops before b loads');
      expect(speaker.calls, contains('load /b.m4a'));
      expect(c.read(voicePlayerProvider).messageId, 'b');

      await p.toggle('b', '/b.m4a');
      expect(c.read(voicePlayerProvider).playing, isFalse);

      await p.cycleSpeed();
      await p.cycleSpeed();
      expect(c.read(voicePlayerProvider).speed, 2.0);
      await p.cycleSpeed();
      expect(c.read(voicePlayerProvider).speed, 1.0);

      await p.seek('b', 0.5);
      expect(speaker.calls.last, 'seek 5');
    });
  });

  // ------------------------------------------------- sending, with retry ---
  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  group('sending a voice note', () {
    late Directory dir;
    late Isar isar;
    late ProviderContainer c;
    late FakeMedia media;
    late FakeSocket socket;

    setUpAll(() async {
      if (haveLib) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      }
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('voice_send');
      isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 'v${DateTime.now().microsecondsSinceEpoch}',
      );
      final service = IsarService.withDb(Future.value(isar))..accountId = 'me';
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      media = FakeMedia();
      socket = FakeSocket();
      c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          isarServiceProvider.overrideWithValue(service),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          webSocketStreamProvider.overrideWith((ref) => const Stream.empty()),
          webSocketServiceProvider.overrideWithValue(socket),
          mediaServiceProvider.overrideWithValue(media),
          chatMediaStoreProvider.overrideWithValue(TempStore(dir)),
        ],
      );
    });

    tearDown(() async {
      c.dispose();
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    Future<String> record() async {
      final f = File(
        '${dir.path}/rec_${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      await f.writeAsBytes([1, 2, 3, 4]);
      return f.path;
    }

    test(
      'uploads, then sends a voice message that refers to the upload',
      () async {
        await c
            .read(chatViewModelProvider.notifier)
            .sendVoice(
              roomId: 'me_bob',
              recipientId: 'bob',
              path: await record(),
              durationMs: 3000,
              waveform: const [1, 2, 3],
            );
        final msg = (await isar.localMessages.where().findAll()).single;
        expect(msg.type, MessageType.audio);
        expect(msg.mediaRemoteId, 'media-${msg.messageId}');
        expect(socket.sent.single['kind'], 'voice');
        expect(socket.sent.single['media_id'], msg.mediaRemoteId);
        expect(socket.sent.single['temp_id'], msg.messageId);
        expect(c.read(voiceUploadProgressProvider), isEmpty);
      },
    );

    test(
      'a failed upload is marked failed; retry reuses the same upload id',
      () async {
        media.failuresLeft = 1;
        final vm = c.read(chatViewModelProvider.notifier);
        await vm.sendVoice(
          roomId: 'me_bob',
          recipientId: 'bob',
          path: await record(),
          durationMs: 3000,
          waveform: const [],
        );
        var msg = (await isar.localMessages.where().findAll()).single;
        expect(msg.status, MessageStatus.failed);
        expect(socket.sent, isEmpty);

        await vm.retryVoice(msg.messageId);
        msg = (await isar.localMessages.where().findAll()).single;
        expect(media.uploads, [msg.messageId, msg.messageId]);
        expect(socket.sent.length, 1);
      },
    );

    test('a received voice note is stored and its audio fetched', () async {
      final vm = c.read(chatViewModelProvider.notifier);
      final service = c.read(isarServiceProvider);
      await service.saveMessage(
        LocalMessage()
          ..messageId = 'srv1'
          ..roomId = 'bob_me'
          ..senderId = 'bob'
          ..recipientId = 'me'
          ..type = MessageType.audio
          ..mediaRemoteId = 'm1'
          ..durationMs = 2000
          ..timestamp = DateTime.utc(2026),
      );
      expect(await vm.downloadVoice('srv1'), isTrue);
      final msg = await service.getMessageById('srv1');
      expect(File(msg!.localMediaPath!).existsSync(), isTrue);
    });
  }, skip: haveLib ? false : 'Isar native library not found');
}
