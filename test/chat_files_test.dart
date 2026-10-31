import 'dart:convert';
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
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/data/services/chat_media_store.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/chat_file_picking.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ------------------------------------------------------------------ fakes ---

typedef Seen = ({
  String method,
  String path,
  Map<String, dynamic> headers,
  List<int> body,
});

/// Answers Dio requests from [handler] and records each one.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options, List<int> body) handler;
  final seen = <Seen>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    seen.add((
      method: options.method,
      path: options.uri.path,
      headers: options.headers,
      body: body,
    ));
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody reply(
  int status, {
  Object? json,
  List<int>? bytes,
  Map<String, String> headers = const {},
}) {
  final data =
      bytes ?? (json == null ? <int>[] : utf8.encode(jsonEncode(json)));
  return ResponseBody.fromBytes(
    data,
    status,
    headers: {
      for (final e in headers.entries) e.key: [e.value],
      if (json != null) 'content-type': ['application/json'],
    },
  );
}

Dio dioWith(FakeAdapter adapter, String base) =>
    Dio(BaseOptions(baseUrl: base))..httpClientAdapter = adapter;

/// The API and Storage steps of sending a file, as the server would answer.
class FakeChatFiles extends ChatFileService {
  FakeChatFiles() : super(Dio(), Dio());

  final announced = <String>[];
  final thumbnails = <Uint8List?>[];
  final uploaded = <String>[];
  final forwards = <(String, String?)>[];
  int failUploads = 0;
  ApiException? refuse;

  @override
  Future<ChatFileUpload> announce({
    required String clientId,
    required ChatFileKind kind,
    required String contentType,
    required int size,
    required String fileName,
    int durationMs = 0,
    Uint8List? thumbnail,
    String? recipientId,
    String? groupId,
  }) async {
    if (refuse case final error?) throw error;
    announced.add('$clientId $contentType $size $fileName');
    thumbnails.add(thumbnail);
    // Like the server: the same client id is the same upload.
    return ChatFileUpload(
      id: 'media-$clientId',
      uploaded: uploaded.contains(clientId),
      uploadPath: 'me/media-$clientId.mp4',
    );
  }

  @override
  Future<void> upload({
    required String clientId,
    required String path,
    required String uploadPath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    if (failUploads > 0) {
      failUploads--;
      throw const ApiException("Can't reach the server.");
    }
    uploaded.add(clientId);
  }

  @override
  Future<ChatFileUpload> complete(String mediaId) async =>
      ChatFileUpload(id: mediaId, uploaded: true);

  @override
  Future<ChatFileUpload> forward(
    String mediaId, {
    required String clientId,
    String? recipientId,
    String? groupId,
  }) async {
    forwards.add((mediaId, recipientId ?? groupId));
    return ChatFileUpload(id: 'copy-of-$mediaId', uploaded: true);
  }

  @override
  Future<void> download(
    String mediaId,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1);
    await File(savePath).writeAsBytes([9, 9, 9]);
  }
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
  Future<String> copyIn(
    String messageId,
    String sourcePath, {
    required String extension,
  }) async =>
      (await File(sourcePath).copy('${dir.path}/$messageId.$extension')).path;

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
  Future<String> pathFor(String messageId, {required String extension}) async =>
      '${dir.path}/$messageId.$extension';
}

void main() {
  // ------------------------------------------------------------- helpers ---
  group('what can be sent', () {
    test('content types follow the extension and must match the kind', () {
      expect(chatFileContentType('clip.MP4', ChatFileKind.video), 'video/mp4');
      expect(
        chatFileContentType('a.mov', ChatFileKind.video),
        'video/quicktime',
      );
      expect(chatFileContentType('song.mp3', ChatFileKind.audio), 'audio/mpeg');
      expect(chatFileContentType('memo.m4a', ChatFileKind.audio), 'audio/mp4');
      // Audio is not a video, and unknown or missing extensions are refused.
      expect(chatFileContentType('song.mp3', ChatFileKind.video), isNull);
      expect(chatFileContentType('setup.exe', ChatFileKind.video), isNull);
      expect(chatFileContentType('noext', ChatFileKind.audio), isNull);
    });

    test('the limit is 35 MB, by size not length', () {
      PickedChatFile file(int size, [String name = 'v.mp4']) => PickedChatFile(
        path: '/x/$name',
        name: name,
        size: size,
        kind: ChatFileKind.video,
      );
      expect(maxChatFileBytes, 35 * 1024 * 1024);
      expect(checkChatFile(file(maxChatFileBytes)).size, maxChatFileBytes);
      expect(
        () => checkChatFile(file(maxChatFileBytes + 1)),
        throwsA(
          isA<ChatFilePickException>().having(
            (e) => e.message,
            'message',
            contains('35 MB'),
          ),
        ),
      );
      expect(
        () => checkChatFile(file(0)),
        throwsA(isA<ChatFilePickException>()),
      );
      expect(
        () => checkChatFile(file(10, 'v.exe')),
        throwsA(isA<ChatFilePickException>()),
      );
    });

    test('sizes read naturally', () {
      expect(formatFileSize(820 * 1024), '820 KB');
      expect(formatFileSize(4404019), '4.2 MB');
      expect(formatFileSize(150 * 1024 * 1024), '150 MB');
    });

    test('server kinds map to message types', () {
      MessageType t(String? k, [bool a = false]) =>
          messageTypeOfKind(k, hasAttachment: a);
      expect(t('video'), MessageType.video);
      expect(t('audio'), MessageType.audioFile);
      expect(t('voice'), MessageType.audio);
      expect(t('sticker'), MessageType.sticker);
      expect(t(null, true), MessageType.image);
      expect(t('text'), MessageType.text);
      expect(isChatFile(MessageType.video), isTrue);
      expect(isChatFile(MessageType.audioFile), isTrue);
      expect(isChatFile(MessageType.audio), isFalse);
    });

    test('previews say what it is', () {
      expect(
        previewTextOf(LocalMessage()..type = MessageType.video),
        '🎬 Video',
      );
      expect(
        previewTextOf(
          LocalMessage()
            ..type = MessageType.audioFile
            ..fileName = 'song.mp3',
        ),
        '🎵 song.mp3',
      );
    });
  });

  // ------------------------------------------------- resumable uploads -----
  group('ChatFileService', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('chat_files');
      file = File('${dir.path}/clip.mp4')
        ..writeAsBytesSync(List.generate(10, (i) => i));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    const location = 'https://ref.supabase.co/storage/v1/upload/resumable/abc';

    test('uploads in pieces from where the server says it is', () async {
      final storage = FakeAdapter((o, body) {
        if (o.method == 'POST') {
          return reply(201, headers: {'location': location});
        }
        final offset = int.parse(o.headers['Upload-Offset'] as String);
        return reply(
          204,
          headers: {'upload-offset': '${offset + body.length}'},
        );
      });
      final service = ChatFileService(
        Dio(),
        dioWith(storage, 'https://ref.supabase.co/storage/v1'),
        chunkSize: 4,
      );
      final progress = <double>[];
      await service.upload(
        clientId: 't1',
        path: file.path,
        uploadPath: 'me/m1.mp4',
        contentType: 'video/mp4',
        onProgress: progress.add,
      );

      final create = storage.seen.first;
      expect(create.path, '/storage/v1/upload/resumable');
      expect(create.headers['Upload-Length'], '10');
      expect(create.headers['Tus-Resumable'], '1.0.0');
      final meta = {
        for (final pair in (create.headers['Upload-Metadata'] as String).split(
          ',',
        ))
          pair.split(' ')[0]: utf8.decode(base64Decode(pair.split(' ')[1])),
      };
      expect(meta['bucketName'], 'chat-media');
      expect(meta['objectName'], 'me/m1.mp4');
      expect(meta['contentType'], 'video/mp4');

      final patches = storage.seen.skip(1).toList();
      expect([for (final p in patches) p.method], ['PATCH', 'PATCH', 'PATCH']);
      expect(
        [for (final p in patches) p.headers['Upload-Offset']],
        ['0', '4', '8'],
      );
      expect([for (final p in patches) p.body.length], [4, 4, 2]);
      expect(patches.expand((p) => p.body).toList(), file.readAsBytesSync());
      expect(progress.last, 1.0);
    });

    test('a retry continues an interrupted upload', () async {
      var failNext = true;
      final storage = FakeAdapter((o, body) {
        if (o.method == 'POST') {
          return reply(201, headers: {'location': location});
        }
        if (o.method == 'HEAD') {
          return reply(200, headers: {'upload-offset': '4'});
        }
        final offset = int.parse(o.headers['Upload-Offset'] as String);
        if (offset == 4 && failNext) {
          failNext = false;
          return reply(500, json: {'message': 'boom'});
        }
        return reply(
          204,
          headers: {'upload-offset': '${offset + body.length}'},
        );
      });
      final service = ChatFileService(
        Dio(),
        dioWith(storage, 'https://ref.supabase.co/storage/v1'),
        chunkSize: 4,
      );
      Future<void> go() => service.upload(
        clientId: 't1',
        path: file.path,
        uploadPath: 'me/m1.mp4',
        contentType: 'video/mp4',
      );
      await expectLater(go(), throwsA(isA<ApiException>()));
      storage.seen.clear();

      await go();
      expect(
        [for (final s in storage.seen) s.method],
        ['HEAD', 'PATCH', 'PATCH'],
      );
      expect(storage.seen[1].headers['Upload-Offset'], '4');
    });

    test('a file already in storage is not sent again', () async {
      final storage = FakeAdapter(
        (o, body) => reply(409, json: {'message': 'exists'}),
      );
      final service = ChatFileService(
        Dio(),
        dioWith(storage, 'https://ref.supabase.co/storage/v1'),
      );
      await service.upload(
        clientId: 't1',
        path: file.path,
        uploadPath: 'me/m1.mp4',
        contentType: 'video/mp4',
      );
      expect([for (final s in storage.seen) s.method], ['POST']);
    });

    test("today's allowance is read from the server", () async {
      final api = FakeAdapter(
        (o, _) => reply(
          200,
          json: {
            'used': 280 * 1024 * 1024,
            'limit': 300 * 1024 * 1024,
            'max_file': 35 * 1024 * 1024,
            'resets_at': '2026-11-01T00:00:00Z',
          },
        ),
      );
      final quota = await ChatFileService(
        dioWith(api, 'https://api.example'),
        Dio(),
      ).quota();
      expect(api.seen.single.path, '/media/usage');
      expect(quota.remaining, 20 * 1024 * 1024);
      expect(quota.maxFile, 35 * 1024 * 1024);
      expect(quota.resetsAt, DateTime.utc(2026, 11));
      // Never negative, even if the server let a race through.
      expect(
        ChatFileQuota(
          used: 301,
          limit: 300,
          maxFile: 1,
          resetsAt: DateTime.utc(2026),
        ).remaining,
        0,
      );
    });

    test('downloads through a signed link, without the app token', () async {
      final api = FakeAdapter(
        (o, _) => reply(
          200,
          json: {
            'url': 'https://cdn.example/signed?token=t',
            'expires_in': 3600,
          },
        ),
      );
      final cdn = FakeAdapter((o, _) => reply(200, bytes: [1, 2, 3]));
      final service = ChatFileService(
        dioWith(api, 'https://api.example')
          ..options.headers['Authorization'] = 'Bearer app-token',
        Dio(),
        downloader: Dio()..httpClientAdapter = cdn,
      );
      final target = '${dir.path}/m1.mp4';
      await service.download('m1', target);

      expect(api.seen.single.path, '/media/m1/url');
      expect(cdn.seen.single.headers.containsKey('Authorization'), isFalse);
      expect(File(target).readAsBytesSync(), [1, 2, 3]);
      expect(File('$target.part').existsSync(), isFalse);
    });
  });

  // ------------------------------------------------------ the view model ---
  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  group('sending and receiving files', () {
    late Directory dir;
    late Isar isar;
    late ProviderContainer c;
    late FakeChatFiles files;
    late FakeSocket socket;
    late List<String> thumbnailed;
    const jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];

    setUpAll(() async {
      if (haveLib) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      }
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('file_send');
      isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 'f${DateTime.now().microsecondsSinceEpoch}',
      );
      final service = IsarService.withDb(Future.value(isar))..accountId = 'me';
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      files = FakeChatFiles();
      socket = FakeSocket();
      thumbnailed = [];
      c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          isarServiceProvider.overrideWithValue(service),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          webSocketEventsProvider.overrideWith((ref) => const Stream.empty()),
          webSocketServiceProvider.overrideWithValue(socket),
          chatFileServiceProvider.overrideWithValue(files),
          videoThumbnailerProvider.overrideWithValue((path) async {
            thumbnailed.add(path);
            return Uint8List.fromList(jpeg);
          }),
          chatMediaStoreProvider.overrideWithValue(TempStore(dir)),
        ],
      );
    });

    tearDown(() async {
      c.dispose();
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    PickedChatFile picked(String name, ChatFileKind kind) {
      final f = File('${dir.path}/picked_$name')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      return PickedChatFile(path: f.path, name: name, size: 5, kind: kind);
    }

    Future<LocalMessage> only() async =>
        (await isar.localMessages.where().findAll()).single;

    Future<void> settle() async {
      // The upload runs in the background after sendFile returns.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test(
      'a video is announced, uploaded, confirmed, then sent by id',
      () async {
        await c
            .read(chatViewModelProvider.notifier)
            .sendFile(
              roomId: 'me_bob',
              recipientId: 'bob',
              file: picked('holiday.mp4', ChatFileKind.video),
            );
        await settle();

        final msg = await only();
        expect(msg.type, MessageType.video);
        expect(msg.fileName, 'holiday.mp4');
        expect(msg.fileSize, 5);
        expect(msg.mediaRemoteId, 'media-${msg.messageId}');
        // The original stays put; the chat keeps its own copy.
        expect(File(msg.localMediaPath!).existsSync(), isTrue);
        expect(
          files.announced.single,
          '${msg.messageId} video/mp4 5 holiday.mp4',
        );
        final payload = socket.sent.single;
        expect(payload['kind'], 'video');
        expect(payload['media_id'], msg.mediaRemoteId);
        expect(payload.containsKey('attachment'), isFalse);
        expect(c.read(fileTransfersProvider), isEmpty);
        // A preview is made from the chat's copy, kept here and sent along.
        expect(thumbnailed, [msg.localMediaPath]);
        expect(File(msg.thumbnailPath!).readAsBytesSync(), jpeg);
        expect(files.thumbnails.single, jpeg);
      },
    );

    test('an audio file in a group goes as kind audio', () async {
      await c
          .read(chatViewModelProvider.notifier)
          .sendFile(
            roomId: 'group_g1',
            recipientId: 'g1',
            groupId: 'g1',
            file: picked('song.mp3', ChatFileKind.audio),
          );
      await settle();
      final msg = await only();
      expect(msg.type, MessageType.audioFile);
      expect(thumbnailed, isEmpty);
      expect(msg.thumbnailPath, isNull);
      expect(socket.sent.single['kind'], 'audio');
      expect(socket.sent.single['group_id'], 'g1');
    });

    test(
      'a failed upload is reported, marked failed, and retried in place',
      () async {
        files.failUploads = 1;
        Object? reported;
        final vm = c.read(chatViewModelProvider.notifier);
        await vm.sendFile(
          roomId: 'me_bob',
          recipientId: 'bob',
          file: picked('holiday.mp4', ChatFileKind.video),
          onError: (e) => reported = e,
        );
        await settle();
        var msg = await only();
        expect(msg.status, MessageStatus.failed);
        expect(reported, isA<ApiException>());
        expect(socket.sent, isEmpty);

        await vm.retryFile(msg.messageId);
        msg = await only();
        // Same client id: the server continues the same upload.
        expect(files.announced.length, 2);
        expect(files.uploaded, [msg.messageId]);
        expect(socket.sent.single['media_id'], 'media-${msg.messageId}');
      },
    );

    test('the server refusing it (not friends) is reported', () async {
      files.refuse = const ApiException(
        'You can only send videos and audio to friends.',
        statusCode: 403,
      );
      Object? reported;
      await c
          .read(chatViewModelProvider.notifier)
          .sendFile(
            roomId: 'me_eve',
            recipientId: 'eve',
            file: picked('holiday.mp4', ChatFileKind.video),
            onError: (e) => reported = e,
          );
      await settle();
      expect((await only()).status, MessageStatus.failed);
      expect('$reported', contains('friends'));
    });

    test('a received file downloads only when asked', () async {
      final service = c.read(isarServiceProvider);
      await service.saveMessage(
        LocalMessage()
          ..messageId = 'srv1'
          ..roomId = 'bob_me'
          ..senderId = 'bob'
          ..recipientId = 'me'
          ..type = MessageType.video
          ..mediaRemoteId = 'm1'
          ..fileName = 'clip.mov'
          ..fileSize = 3
          ..timestamp = DateTime.utc(2026),
      );
      expect((await service.getMessageById('srv1'))!.localMediaPath, isNull);
      expect(
        await c.read(chatViewModelProvider.notifier).downloadFile('srv1'),
        isTrue,
      );
      final msg = await service.getMessageById('srv1');
      expect(msg!.localMediaPath, endsWith('srv1.mov'));
      expect(File(msg.localMediaPath!).readAsBytesSync(), [9, 9, 9]);
      // Sent without a preview (from a desktop): one is made here.
      expect(thumbnailed, [msg.localMediaPath]);
      expect(File(msg.thumbnailPath!).readAsBytesSync(), jpeg);
    });

    test('forwarding copies on the server and keeps a local copy', () async {
      final local = File('${dir.path}/src.mp4')..writeAsBytesSync([7, 7]);
      final source = LocalMessage()
        ..messageId = 'source'
        ..roomId = 'alice_me'
        ..senderId = 'alice'
        ..recipientId = 'me'
        ..type = MessageType.video
        ..status = MessageStatus.sent
        ..mediaRemoteId = 'remote-video'
        ..localMediaPath = local.path
        ..fileName = 'clip.mp4'
        ..fileSize = 2
        ..thumbnailPath = (File(
          '${dir.path}/src.thumb.jpg',
        )..writeAsBytesSync(jpeg)).path
        ..timestamp = DateTime.utc(2026);
      await isar.writeTxn(() => isar.localMessages.put(source));

      final ok = await c
          .read(chatViewModelProvider.notifier)
          .forwardMessage(source: source, recipientId: 'bob');

      expect(ok, isTrue);
      expect(files.forwards, [('remote-video', 'bob')]);
      expect(files.announced, isEmpty); // nothing uploaded again
      expect(socket.sent.single['kind'], 'video');
      expect(socket.sent.single['media_id'], 'copy-of-remote-video');
      final copy = (await isar.localMessages.where().findAll()).singleWhere(
        (m) => m.roomId == 'bob_me',
      );
      expect(copy.forwarded, isTrue);
      expect(copy.fileName, 'clip.mp4');
      // Its own file, so deleting one message never breaks the other.
      expect(copy.localMediaPath, isNot(local.path));
      expect(File(copy.localMediaPath!).readAsBytesSync(), [7, 7]);
      expect(copy.thumbnailPath, isNot(source.thumbnailPath));
      expect(File(copy.thumbnailPath!).readAsBytesSync(), jpeg);
    });
  }, skip: haveLib ? false : 'Isar native library not found');
}
