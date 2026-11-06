import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/data/services/official_service.dart';
import 'package:serafim/src/presentation/view/official_chat_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Announcement withVideo({String content = 'Watch this', String id = 'a1'}) =>
    Announcement(
      id: id,
      content: content,
      createdAt: DateTime.utc(2026, 11, 6),
      video: const AnnouncementVideo(
        name: 'intro.mp4',
        contentType: 'video/mp4',
        size: 5 * 1024 * 1024,
        durationMs: 65000,
      ),
    );

class _Service extends OfficialService {
  _Service() : super(Dio());

  final log = <String>[];
  Map<String, dynamic>? posted;
  String? postedText;
  String? refuse;

  @override
  Future<OfficialChatInfo> info() async => const OfficialChatInfo(
    name: 'SERAFIM',
    username: 'serafim',
    canPost: true,
  );

  @override
  Future<List<Announcement>> announcements({
    DateTime? before,
    int limit = 50,
  }) async => const [];

  @override
  Future<String> startVideoUpload({
    required String contentType,
    required int size,
  }) async {
    log.add('start $contentType $size');
    if (refuse != null) throw ApiException(refuse!);
    return 'me/announcement-1.mp4';
  }

  @override
  Future<Announcement> post(
    String content, {
    AppUpdate? update,
    Map<String, dynamic>? video,
  }) async {
    log.add('post');
    posted = video;
    postedText = content;
    return withVideo(
      content: content.isEmpty ? videoOnlyAnnouncementText : content,
    );
  }

  @override
  Future<void> delete(String id) async => log.add('delete $id');
}

class _Listing extends _Service {
  _Listing({required this.admin});
  final bool admin;

  @override
  Future<OfficialChatInfo> info() async =>
      OfficialChatInfo(name: 'SERAFIM', username: 'serafim', canPost: admin);

  @override
  Future<List<Announcement>> announcements({
    DateTime? before,
    int limit = 50,
  }) async => [
    withVideo(),
    withVideo(id: 'a2', content: videoOnlyAnnouncementText),
  ];
}

class _Files extends ChatFileService {
  _Files(this.log) : super(Dio(), Dio());
  final List<String> log;

  @override
  Future<void> upload({
    required String clientId,
    required String path,
    required String uploadPath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    log.add('upload $uploadPath');
    onProgress?.call(1);
  }
}

class _Store implements OfficialVideoStore {
  final fetched = <String>[];
  Object? failure;

  @override
  Future<String> fileFor(
    Announcement announcement, {
    void Function(double progress)? onProgress,
  }) async {
    if (failure != null) throw failure!;
    fetched.add(announcement.id);
    return '/videos/${announcement.id}.mp4';
  }

  @override
  Future<void> forget(String announcementId) async {}
}

const _file = PickedChatFile(
  path: '/x/intro.mp4',
  name: 'intro.mp4',
  size: 1000,
  kind: ChatFileKind.video,
  durationMs: 9000,
);

void main() {
  group('the model', () {
    test('survives being saved on the phone', () {
      final back = Announcement.fromJson(withVideo().toJson());
      expect(back.video!.name, 'intro.mp4');
      expect(back.video!.size, 5 * 1024 * 1024);
      expect(back.video!.durationMs, 65000);
    });

    test('announcements without a video are as before', () {
      final a = Announcement.fromJson({
        'id': 'x',
        'content': 'hi',
        'created_at': '2026-11-06T10:00:00Z',
      });
      expect(a.video, isNull);
      expect(a.caption, 'hi');
    });

    test('a video with no words shows none, but notifications still do', () {
      final a = withVideo(content: videoOnlyAnnouncementText);
      expect(a.caption, '');
      expect(a.preview, videoOnlyAnnouncementText);
      expect(withVideo().caption, 'Watch this');
    });
  });

  group('posting', () {
    Future<(ProviderContainer, _Service)> make() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = _Service();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localCacheProvider.overrideWithValue(LocalCache(prefs)),
          currentAccountIdProvider.overrideWithValue('me'),
          officialServiceProvider.overrideWithValue(service),
          chatFileServiceProvider.overrideWithValue(_Files(service.log)),
          videoThumbnailerProvider.overrideWithValue(
            (_) async => Uint8List.fromList([0xFF, 0xD8]),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(officialChatProvider.future);
      return (c, service);
    }

    test('uploads first, only then announces, and it appears', () async {
      final (c, service) = await make();
      var progress = 0.0;
      final error = await c
          .read(officialChatProvider.notifier)
          .postVideo(
            _file,
            content: ' Hello ',
            onProgress: (p) => progress = p,
          );
      expect(error, isNull);
      expect(service.log, [
        'start video/mp4 1000',
        'upload me/announcement-1.mp4',
        'post',
      ]);
      expect(progress, 1);
      expect(service.postedText, 'Hello');
      expect(service.posted!['upload_path'], 'me/announcement-1.mp4');
      expect(service.posted!['duration_ms'], 9000);
      expect(service.posted!['thumbnail'], isNotEmpty);
      expect(c.read(officialChatProvider).value!.latest!.video, isNotNull);
    });

    test('a video needs no words', () async {
      final (c, service) = await make();
      expect(
        await c.read(officialChatProvider.notifier).postVideo(_file),
        isNull,
      );
      expect(service.postedText, '');
    });

    test('a refusal is said, and nothing is announced', () async {
      final (c, service) = await make();
      service.refuse = 'Videos can be up to 35 MB.';
      final error = await c
          .read(officialChatProvider.notifier)
          .postVideo(_file);
      expect(error, contains('35 MB'));
      expect(service.log, isNot(contains('post')));
      expect(c.read(officialChatProvider).value!.latest, isNull);
    });

    test('a file of the wrong kind never reaches the server', () async {
      final (c, service) = await make();
      final error = await c
          .read(officialChatProvider.notifier)
          .postVideo(
            const PickedChatFile(
              path: '/x/a.exe',
              name: 'a.exe',
              size: 1,
              kind: ChatFileKind.video,
            ),
          );
      expect(error, isNotNull);
      expect(service.log, isEmpty);
    });
  });

  group('in the official chat', () {
    Future<void> show(WidgetTester t, {required bool admin}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            localCacheProvider.overrideWithValue(LocalCache(prefs)),
            currentAccountIdProvider.overrideWithValue('me'),
            officialServiceProvider.overrideWithValue(_Listing(admin: admin)),
            officialVideoStoreProvider.overrideWithValue(_Store()),
          ],
          child: const MaterialApp(home: OfficialChatPage()),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('admins can attach a video; everyone else cannot', (t) async {
      await show(t, admin: true);
      expect(find.byKey(const ValueKey('attach-button')), findsOneWidget);
      await show(t, admin: false);
      expect(find.byKey(const ValueKey('attach-button')), findsNothing);
    });

    testWidgets('a video shows, with its words but no placeholder', (t) async {
      await show(t, admin: false);
      expect(
        find.byKey(const ValueKey('announcement-video-a1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('announcement-video-a2')),
        findsOneWidget,
      );
      expect(find.text('Watch this'), findsOneWidget);
      expect(find.text(videoOnlyAnnouncementText), findsNothing);
    });
  });

  group('watching', () {
    Future<_Store> show(
      WidgetTester t,
      void Function(String path, String title) played,
    ) async {
      final store = _Store();
      await t.pumpWidget(
        ProviderScope(
          overrides: [officialVideoStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            home: Scaffold(
              body: AnnouncementVideoCard(
                announcement: withVideo(),
                play: (_, path, title) => played(path, title),
              ),
            ),
          ),
        ),
      );
      return store;
    }

    final card = find.byKey(const ValueKey('announcement-video-a1'));

    testWidgets('shows its length and size, and fetches nothing yet', (
      t,
    ) async {
      final store = await show(t, (_, _) {});
      expect(
        find.text('1:05 · ${formatFileSize(5 * 1024 * 1024)}'),
        findsOneWidget,
      );
      expect(store.fetched, isEmpty);
    });

    testWidgets('tapping fetches it and plays it', (t) async {
      String? played;
      final store = await show(t, (path, _) => played = path);
      await t.tap(card);
      await t.pump();
      await t.pump();
      expect(store.fetched, ['a1']);
      expect(played, '/videos/a1.mp4');
    });

    testWidgets('a failure says so, and can be tried again', (t) async {
      String? played;
      final store = await show(t, (path, _) => played = path);
      store.failure = const ApiException('No connection.');
      await t.tap(card);
      await t.pump();
      await t.pump();
      expect(played, isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      store.failure = null;
      await t.tap(card);
      await t.pump();
      await t.pump();
      expect(played, isNotNull);
    });
  });
}
