import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/utils/echo_icon.dart';
import 'package:serafim/src/data/models/echo.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/moment.dart';
import 'package:serafim/src/data/services/moment_media_cache.dart';
import 'package:serafim/src/data/services/moment_service.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/view/moment_viewer_page.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/presentation/view/widgets/moments_strip.dart';
import 'package:serafim/src/presentation/view/moment_composer_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/moment_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/moment_ring.dart';
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A real 1x1 picture: the screens decode what they are given.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
final _thumb = base64Encode(_png);

Map<String, dynamic> momentJson(
  String id, {
  bool allowSave = true,
  String user = 'ann',
  String kind = 'photo',
  String? caption,
  String visibility = 'friends',
  bool seen = false,
  bool sparked = false,
  int sparks = 0,
  int? views,
  List<String>? excluded,
}) => {
  'id': id,
  'user_id': user,
  'kind': kind,
  'caption': caption,
  'visibility': visibility,
  'allow_save': allowSave,
  'duration_ms': kind == 'video' ? 30000 : 0,
  'created_at': DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 2))
      .toIso8601String(),
  'expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 22))
      .toIso8601String(),
  'thumbnail': _thumb,
  'seen': seen,
  'sparked': sparked,
  'spark_count': sparks,
  'view_count': views,
  'exclude_ids': excluded,
};

Moment moment(
  String id, {
  bool allowSave = true,
  String user = 'ann',
  String? caption,
  bool seen = false,
  bool sparked = false,
  int sparks = 0,
  int? views,
}) => Moment.fromJson(
  momentJson(
    id,
    allowSave: allowSave,
    user: user,
    caption: caption,
    seen: seen,
    sparked: sparked,
    sparks: sparks,
    views: views,
  ),
);

/// Records requests and answers from a table of canned JSON.
class Recorder implements HttpClientAdapter {
  Recorder(this.answers);
  final Map<String, Object?> answers;
  final calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    calls.add(o);
    final key = '${o.method} ${o.path}';
    final answer = answers[key];
    if (answer is List<int>) {
      return ResponseBody.fromBytes(
        answer,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/jpeg'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(answer ?? {}),
      answer == null ? 204 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A service whose answers the test controls.
class FakeMoments extends MomentService {
  FakeMoments() : super(Dio());

  Map<String, List<Moment>> byUser = {};
  Map<String, MomentRing> ringAnswers = {};
  final ringCalls = <List<String>>[];
  final seen = <String>[];
  final sparked = <String>[];
  final unsparked = <String>[];
  final deleted = <String>[];
  bool failSparks = false;
  MomentViewers viewerList = const MomentViewers(viewers: [], sparkCount: 0);

  @override
  Future<List<Moment>> of(String userId) async => byUser[userId] ?? const [];

  @override
  Future<List<Moment>> mine() async => byUser['me'] ?? const [];

  @override
  Future<List<MomentRing>> rings(Iterable<String> userIds) async {
    ringCalls.add(userIds.toList());
    return [
      for (final id in userIds)
        if (ringAnswers[id] != null) ringAnswers[id]!,
    ];
  }

  List<MomentRing> feedAnswer = [];

  @override
  Future<List<MomentRing>> feed() async => feedAnswer;

  @override
  Future<Uint8List> photo(String id) async => _png;

  final seenPrivately = <String>[];

  @override
  Future<void> markSeen(String id, {bool private = false}) async {
    seen.add(id);
    if (private) seenPrivately.add(id);
  }

  @override
  Future<Moment> spark(String id) async {
    if (failSparks) throw StateError('no');
    sparked.add(id);
    return byUser.values
        .expand((m) => m)
        .firstWhere((m) => m.id == id)
        .copyWith(sparked: true, sparkCount: 1);
  }

  @override
  Future<Moment> unspark(String id) async {
    unsparked.add(id);
    return byUser.values
        .expand((m) => m)
        .firstWhere((m) => m.id == id)
        .copyWith(sparked: false, sparkCount: 0);
  }

  @override
  Future<MomentViewers> viewers(String id) async => viewerList;

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

MomentRing ring(String user, {bool allSeen = false, int count = 1}) =>
    MomentRing(
      userId: user,
      count: count,
      latestAt: DateTime.utc(2026),
      allSeen: allSeen,
    );

/// The real actions, except that saving to the gallery is recorded.
class FakeActions extends MomentActions {
  FakeActions(super.ref);
  static final saved = <String>[];

  @override
  Future<String> save(Moment moment, {required String ownerLabel}) async {
    saved.add('${moment.id}:$ownerLabel');
    return 'Saved to your gallery (Serafim album)';
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

/// Records what the viewer sends as a reply.
class FakeChat extends ChatViewModel {
  static final replies = <({String to, String text, MomentPreview? about})>[];

  @override
  ChatState build() => const ChatState();

  @override
  Future<void> replyToMoment({
    required String roomId,
    required String recipientId,
    required String content,
    required MomentPreview about,
  }) async {
    replies.add((to: recipientId, text: content, about: about));
  }
}

void main() {
  // ------------------------------------------------------------ the data ---

  group('the service', () {
    test('reads moments, rings and viewers', () async {
      final recorder = Recorder({
        'GET /moments/users/ann': [
          momentJson('m1', caption: 'Sunset', sparks: 2),
        ],
        'GET /moments/rings': [
          {
            'user_id': 'ann',
            'count': 2,
            'latest_at': '2026-01-01T00:00:00Z',
            'all_seen': false,
          },
        ],
        'GET /moments/m1/viewers': {
          'viewers': [
            {
              'person': {
                'id': 'bo',
                'username': 'bo',
                'display_name': 'Bo B',
                'profile_pic': null,
              },
              'viewed_at': '2026-01-01T00:00:00Z',
              'sparked': true,
            },
          ],
          'spark_count': 1,
        },
      });
      final service = MomentService(Dio()..httpClientAdapter = recorder);

      final moments = await service.of('ann');
      expect(moments.single.caption, 'Sunset');
      expect(moments.single.sparkCount, 2);
      expect(moments.single.thumbnail, _png);
      expect(moments.single.audience, MomentAudience.friends);

      final rings = await service.rings(['ann', 'bo']);
      expect(recorder.calls.last.queryParameters, {'user_ids': 'ann,bo'});
      expect(rings.single.count, 2);

      final viewers = await service.viewers('m1');
      expect(viewers.viewers.single.displayName, 'Bo B');
      expect(viewers.viewers.single.sparked, isTrue);
    });

    test('posts what the server expects', () async {
      final recorder = Recorder({
        'POST /moments': momentJson('new', caption: 'Hi'),
      });
      final service = MomentService(Dio()..httpClientAdapter = recorder);

      await service.postPhoto(
        photo: Uint8List.fromList([1, 2]),
        thumbnail: Uint8List.fromList([3]),
        audience: MomentAudience.except,
        excludeIds: ['x', 'y'],
        caption: '  Hi  ',
      );
      final body = recorder.calls.last.data as Map<String, dynamic>;
      expect(body['kind'], 'photo');
      expect(body['visibility'], 'except');
      expect(body['exclude_ids'], ['x', 'y']);
      expect(body['caption'], 'Hi');
      expect(base64Decode(body['photo'] as String), [1, 2]);

      await service.postPhoto(
        photo: Uint8List.fromList([1]),
        thumbnail: Uint8List.fromList([3]),
        audience: MomentAudience.everyone,
        excludeIds: ['x'],
        caption: '   ',
      );
      final plain = recorder.calls.last.data as Map<String, dynamic>;
      expect(plain['visibility'], 'public'); // what the server calls it
      expect(plain.containsKey('exclude_ids'), isFalse);
      expect(plain.containsKey('caption'), isFalse);
    });

    test('the audience names match the server', () {
      expect(MomentAudience.everyone.wire, 'public');
      expect(MomentAudience.friends.wire, 'friends');
      expect(MomentAudience.except.wire, 'except');
      expect(MomentAudience.fromWire('public'), MomentAudience.everyone);
      expect(MomentAudience.fromWire('except'), MomentAudience.except);
      expect(MomentAudience.fromWire('anything else'), MomentAudience.friends);
    });
  });

  group('the rings', () {
    late FakeMoments service;
    late ProviderContainer c;

    setUp(() {
      service = FakeMoments();
      c = ProviderContainer(
        overrides: [
          momentServiceProvider.overrideWithValue(service),
          currentAccountIdProvider.overrideWithValue('me'),
        ],
      );
      addTearDown(c.dispose);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 150));

    test('avatars asking at the same moment make one request', () async {
      service.ringAnswers = {
        'ann': ring('ann'),
        'bo': ring('bo', allSeen: true),
      };
      final rings = c.read(momentRingsProvider.notifier);
      rings
        ..request('ann')
        ..request('bo')
        ..request('cy');
      await settle();
      expect(service.ringCalls, hasLength(1));
      expect(service.ringCalls.single.toSet(), {'ann', 'bo', 'cy'});
      final state = c.read(momentRingsProvider);
      expect(state.keys.toSet(), {'ann', 'bo'});
      expect(state['bo']!.allSeen, isTrue);
    });

    test('the same person is not asked about again straight away', () async {
      final rings = c.read(momentRingsProvider.notifier);
      rings.request('ann');
      await settle();
      rings.request('ann');
      await settle();
      expect(service.ringCalls, hasLength(1));
      // Two minutes later they are.
      rings.request('ann', now: DateTime.now().add(const Duration(minutes: 3)));
      await settle();
      expect(service.ringCalls, hasLength(2));
    });

    test('someone whose moments ended loses their ring', () async {
      service.ringAnswers = {'ann': ring('ann')};
      final rings = c.read(momentRingsProvider.notifier);
      await rings.refresh(['ann']);
      expect(c.read(momentRingsProvider).keys, ['ann']);
      service.ringAnswers = {};
      await rings.refresh(['ann']);
      expect(c.read(momentRingsProvider), isEmpty);
    });

    test('a failed lookup leaves what is shown alone', () async {
      service.ringAnswers = {'ann': ring('ann')};
      final rings = c.read(momentRingsProvider.notifier);
      await rings.refresh(['ann']);
      final failing = _Failing();
      final other = ProviderContainer(
        overrides: [
          momentServiceProvider.overrideWithValue(failing),
          currentAccountIdProvider.overrideWithValue('me'),
        ],
      );
      addTearDown(other.dispose);
      await other.read(momentRingsProvider.notifier).refresh(['ann']);
      expect(other.read(momentRingsProvider), isEmpty);
      expect(c.read(momentRingsProvider).keys, ['ann']);
    });

    test('looking at everything turns the ring quiet', () async {
      service.ringAnswers = {'ann': ring('ann')};
      final rings = c.read(momentRingsProvider.notifier);
      await rings.refresh(['ann']);
      expect(
        MomentRingState.of(c.read(momentRingsProvider)['ann']),
        MomentRingState.unseen,
      );
      rings.markSeen('ann');
      expect(
        MomentRingState.of(c.read(momentRingsProvider)['ann']),
        MomentRingState.seen,
      );
      expect(MomentRingState.of(null), MomentRingState.none);
    });
  });

  // ---------------------------------------------------------- the avatar ---

  group('the avatar', () {
    Future<void> show(
      WidgetTester t,
      MomentRingState ring, {
      bool halo = false,
    }) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AvatarThumb(size: 60, ring: ring, halo: halo),
          ),
        ),
      ),
    );

    testWidgets('no moment, no ring', (t) async {
      await show(t, MomentRingState.none);
      expect(find.bySemanticsLabel('Has a new moment'), findsNothing);
      expect(t.getSize(find.byType(AvatarThumb)), const Size(60, 60));
    });

    testWidgets('a new moment is a bright ring, a seen one a quiet one', (
      t,
    ) async {
      await show(t, MomentRingState.unseen);
      expect(find.bySemanticsLabel('Has a new moment'), findsOneWidget);
      await show(t, MomentRingState.seen);
      expect(find.bySemanticsLabel('Has a moment'), findsOneWidget);
      // The avatar takes the same room either way.
      expect(t.getSize(find.byType(AvatarThumb)), const Size(60, 60));
    });

    testWidgets('the halo sits inside the ring, the picture inside both', (
      t,
    ) async {
      await show(t, MomentRingState.unseen, halo: true);
      final frame = t.getRect(find.byType(MomentRingFrame));
      final halo = t.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.label == 'Halo on: free to chat',
        ),
      );
      expect(frame.size, const Size(60, 60));
      expect(
        frame.contains(halo.topLeft) && frame.contains(halo.bottomRight),
        isTrue,
      );
      expect(halo.width, lessThanOrEqualTo(60 - momentRingSpace + 0.01));
      expect(halo.width, greaterThan(40));
    });
  });

  group('tapping a ringed avatar', () {
    late FakeMoments service;
    setUp(() => service = FakeMoments());

    Future<void> pump(WidgetTester t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            momentServiceProvider.overrideWithValue(service),
            currentAccountIdProvider.overrideWithValue('me'),
            chatViewModelProvider.overrideWith(FakeChat.new),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: TappableAvatar(
                  image: null,
                  heroTag: 't',
                  name: 'Ann',
                  userId: 'ann',
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 200));
    }

    testWidgets('with moments it plays them', (t) async {
      service
        ..ringAnswers = {'ann': ring('ann')}
        ..byUser = {
          'ann': [moment('m1', caption: 'Hello')],
        };
      await pump(t);
      await t.tap(find.byType(TappableAvatar));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentViewerPage), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('without any it opens the photo as before', (t) async {
      await pump(t);
      await t.tap(find.byType(TappableAvatar));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentViewerPage), findsNothing);
    });
  });

  // ---------------------------------------------------------- the viewer ---

  group('getting moments ready ahead', () {
    late Directory dir;
    late FakeMoments service;
    late ProviderContainer container;
    final calls = <String>[];

    setUp(() {
      dir = Directory.systemTemp.createTempSync('moment_prefetch');
      calls.clear();
      service = FakeMoments()
        ..byUser = {
          'ann': [moment('a'), moment('b', seen: true)],
          'bo': [moment('c')],
        };
      container = ProviderContainer(
        overrides: [
          momentServiceProvider.overrideWithValue(service),
          currentAccountIdProvider.overrideWithValue('me'),
          momentMediaCacheProvider.overrideWith(
            (ref) =>
                MomentMediaCache(directory: () async => dir, useProxy: false),
          ),
        ],
      );
      addTearDown(() {
        container.dispose();
        dir.deleteSync(recursive: true);
      });
    });

    MomentRing ring(String id, {bool allSeen = false}) => MomentRing(
      userId: id,
      count: 1,
      latestAt: DateTime.utc(2026, 1, 1),
      allSeen: allSeen,
    );

    test(
      'unseen photos are saved and the list is kept for the viewer',
      () async {
        final prefetcher = container.read(momentPrefetcherProvider);
        await prefetcher.prefetch([ring('ann'), ring('bo', allSeen: true)]);
        expect(File('${dir.path}/a.jpg').existsSync(), isTrue);
        expect(File('${dir.path}/b.jpg').existsSync(), isFalse, reason: 'seen');
        expect(
          File('${dir.path}/c.jpg').existsSync(),
          isFalse,
          reason: 'no news',
        );
        expect(prefetcher.take('ann')?.map((m) => m.id), ['a', 'b']);
        expect(prefetcher.take('ann'), isNull, reason: 'used once');
      },
    );

    test(
      'the viewer opens the list fetched ahead without asking again',
      () async {
        await container.read(momentPrefetcherProvider).prefetch([ring('ann')]);
        service.byUser = {};
        final list = await container.read(userMomentsProvider('ann').future);
        expect(list.map((m) => m.id), ['a', 'b']);
      },
    );

    test(
      'your own are not fetched ahead, and a failure is not fatal',
      () async {
        await container.read(momentPrefetcherProvider).prefetch([ring('me')]);
        expect(dir.listSync(), isEmpty);
      },
    );
  });

  group('the viewer', () {
    late FakeMoments service;
    setUp(() {
      service = FakeMoments();
      FakeChat.replies.clear();
    });

    Future<void> open(
      WidgetTester t, {
      String user = 'ann',
      bool readReceipts = true,
    }) async {
      SharedPreferences.setMockInitialValues({
        'settings.readReceipts': readReceipts,
      });
      final prefs = await SharedPreferences.getInstance();
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            momentServiceProvider.overrideWithValue(service),
            currentAccountIdProvider.overrideWithValue('me'),
            chatViewModelProvider.overrideWith(FakeChat.new),
            momentActionsProvider.overrideWith(FakeActions.new),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      openMoments(context, userId: user, name: 'Ann'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    Finder bar(int i) => find.byKey(ValueKey('moment-bar-$i'));
    double barValue(WidgetTester t, int i) =>
        t.widget<MomentProgressBar>(bar(i)).value;

    testWidgets('starts at the first one you have not seen and says so', (
      t,
    ) async {
      service.byUser = {
        'ann': [
          moment('a', seen: true, caption: 'first'),
          moment('b', caption: 'second'),
          moment('c', caption: 'third'),
        ],
      };
      await open(t);
      expect(find.text('second'), findsOneWidget);
      expect(bar(0), findsOneWidget);
      expect(bar(2), findsOneWidget);
      expect(barValue(t, 0), 1); // already played
      expect(service.seen, ['b']);
    });

    testWidgets('when the last one ends it closes, once, and only itself', (
      t,
    ) async {
      service.byUser = {
        'ann': [moment('a', caption: 'one')],
      };
      await open(t);
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentViewerPage), findsNothing);
      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'the page beneath stays',
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('a photo plays for five seconds, then the next', (t) async {
      service.byUser = {
        'ann': [moment('a', caption: 'one'), moment('b', caption: 'two')],
      };
      await open(t);
      expect(find.text('one'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2500));
      expect(barValue(t, 0), closeTo(0.5, 0.1));
      await t.pump(const Duration(milliseconds: 2600));
      await t.pump();
      expect(find.text('two'), findsOneWidget);
      expect(service.seen, ['a', 'b']);
    });

    testWidgets(
      'tapping the right goes on, the left goes back, the end closes',
      (t) async {
        service.byUser = {
          'ann': [moment('a', caption: 'one'), moment('b', caption: 'two')],
        };
        await open(t);
        final surface = t.getRect(find.byKey(const ValueKey('moment-surface')));
        await t.tapAt(Offset(surface.right - 40, surface.center.dy));
        await t.pump();
        expect(find.text('two'), findsOneWidget);
        // Some way in, the left starts this one again…
        await t.pump(const Duration(seconds: 2));
        await t.tapAt(Offset(surface.left + 20, surface.center.dy));
        await t.pump();
        expect(find.text('two'), findsOneWidget);
        expect(barValue(t, 1), lessThan(0.05));
        // …and right at the start, it goes back to the one before.
        await t.tapAt(Offset(surface.left + 20, surface.center.dy));
        await t.pump();
        expect(find.text('one'), findsOneWidget);
        await t.tapAt(Offset(surface.right - 40, surface.center.dy));
        await t.pump();
        await t.tapAt(Offset(surface.right - 40, surface.center.dy));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byType(MomentViewerPage), findsNothing);
      },
    );

    testWidgets('holding a finger down pauses it', (t) async {
      service.byUser = {
        'ann': [moment('a', caption: 'one')],
      };
      await open(t);
      await t.pump(const Duration(seconds: 1));
      final before = barValue(t, 0);
      final gesture = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('moment-surface'))),
      );
      // The show runs until the long press (half a second) takes hold.
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 300));
      final held = barValue(t, 0);
      await t.pump(const Duration(seconds: 3));
      expect(barValue(t, 0), held);
      expect(held, greaterThan(before));
      await gesture.up();
      await t.pump(); // the show starts again…
      await t.pump(const Duration(milliseconds: 500)); // …and runs
      expect(barValue(t, 0), greaterThan(held));
    });

    testWidgets('sparking is instant, and undone if it fails', (t) async {
      service.byUser = {
        'ann': [moment('a')],
      };
      await open(t);
      await t.tap(find.byKey(const ValueKey('moment-spark')));
      await t.pump();
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      await t.pump(const Duration(milliseconds: 50));
      expect(service.sparked, ['a']);
      await t.tap(find.byKey(const ValueKey('moment-spark')));
      await t.pump(const Duration(milliseconds: 50));
      expect(service.unsparked, ['a']);

      service.failSparks = true;
      await t.tap(find.byKey(const ValueKey('moment-spark')));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.bolt_outlined), findsOneWidget); // back
      expect(find.text("Couldn't do that."), findsOneWidget);
    });

    testWidgets('a reply goes to the owner, about that moment', (t) async {
      service.byUser = {
        'ann': [moment('a', caption: 'Sunset')],
      };
      await open(t);
      // Typing swaps the heart for send.
      expect(find.byKey(const ValueKey('moment-send-reply')), findsNothing);
      await t.enterText(
        find.byKey(const ValueKey('moment-reply')),
        '  Love it  ',
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('moment-send-reply')));
      await t.pump(const Duration(milliseconds: 50));
      expect(FakeChat.replies, hasLength(1));
      final reply = FakeChat.replies.single;
      expect(reply.to, 'ann');
      expect(reply.text, 'Love it');
      expect(reply.about!.id, 'a');
      expect(reply.about!.caption, 'Sunset');
      expect(find.text('Reply sent to Ann.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moment-spark')),
        findsOneWidget,
      ); // empty again
    });

    testWidgets('typing a reply holds the show', (t) async {
      service.byUser = {
        'ann': [moment('a'), moment('b', caption: 'two')],
      };
      await open(t);
      await t.tap(find.byKey(const ValueKey('moment-reply')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 8));
      expect(find.text('two'), findsNothing); // still on the first
    });

    testWidgets(
      'Save keeps it, and is gone when the owner switched saving off',
      (t) async {
        FakeActions.saved.clear();
        service.byUser = {
          'ann': [
            moment('a', caption: 'one'),
            moment('b', allowSave: false, caption: 'two'),
          ],
        };
        await open(t);
        expect(find.byKey(const ValueKey('moment-save')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('moment-save')));
        await t.pump(const Duration(milliseconds: 50));
        expect(FakeActions.saved, ['a:Ann']);
        expect(
          find.text('Saved to your gallery (Serafim album)'),
          findsOneWidget,
        );

        final surface = t.getRect(find.byKey(const ValueKey('moment-surface')));
        await t.tapAt(Offset(surface.right - 40, surface.center.dy));
        await t.pump();
        expect(find.text('two'), findsOneWidget);
        expect(find.byKey(const ValueKey('moment-save')), findsNothing);
      },
    );

    testWidgets('you can always save your own', (t) async {
      FakeActions.saved.clear();
      service.byUser = {
        'me': [moment('a', user: 'me', allowSave: false, views: 0)],
      };
      await open(t, user: 'me');
      await t.tap(find.byKey(const ValueKey('moment-save')));
      await t.pump(const Duration(milliseconds: 50));
      expect(FakeActions.saved, hasLength(1));
    });

    testWidgets('with read receipts off, the owner is not told you looked', (
      t,
    ) async {
      service.byUser = {
        'ann': [moment('a')],
      };
      await open(t, readReceipts: false);
      expect(service.seen, ['a']);
      expect(service.seenPrivately, ['a']);
    });

    testWidgets('with read receipts on, you are counted', (t) async {
      service.byUser = {
        'ann': [moment('a')],
      };
      await open(t);
      expect(service.seen, ['a']);
      expect(service.seenPrivately, isEmpty);
    });

    testWidgets('the progress strip is square-cornered, in the app colours', (
      t,
    ) async {
      service.byUser = {
        'ann': [moment('a'), moment('b')],
      };
      await open(t);
      final decoration =
          t
                  .widget<Container>(
                    find
                        .descendant(
                          of: bar(0),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(decoration.borderRadius, isNull);
      expect(decoration.border, isNotNull);
    });

    testWidgets('moments that have ended say so and close', (t) async {
      service.byUser = {'ann': []};
      await open(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentViewerPage), findsNothing);
      expect(find.textContaining('has ended'), findsOneWidget);
    });

    testWidgets('your own show who saw them, not a reply box', (t) async {
      service
        ..byUser = {
          'me': [moment('a', user: 'me', views: 3, sparks: 1)],
        }
        ..viewerList = MomentViewers(
          sparkCount: 1,
          viewers: [
            MomentViewer(
              userId: 'bo',
              username: 'bo',
              displayName: 'Bo B',
              viewedAt: DateTime.now().toUtc(),
              sparked: true,
            ),
            MomentViewer(
              userId: 'cy',
              username: 'cy',
              displayName: 'Cy C',
              viewedAt: DateTime.now().toUtc(),
              sparked: false,
            ),
          ],
        );
      await open(t, user: 'me');
      expect(find.byKey(const ValueKey('moment-reply')), findsNothing);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('moment-view-count'))).data,
        '3',
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('moment-spark-count'))).data,
        '1',
      );
      expect(service.seen, isEmpty); // your own look doesn't count

      await t.tap(find.byKey(const ValueKey('moment-viewers')));
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('2 people saw this · 1 Spark'), findsOneWidget);
      expect(find.text('Bo B'), findsOneWidget);
      expect(find.text('Cy C'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsNWidgets(2)); // the count, and Bo's
    });

    testWidgets('you can delete your own, after asking', (t) async {
      service.byUser = {
        'me': [moment('a', user: 'me', views: 0)],
      };
      await open(t, user: 'me');
      await t.tap(find.byKey(const ValueKey('moment-delete')));
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(service.deleted, isEmpty);
      await t.tap(find.byKey(const ValueKey('moment-delete-confirm')));
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(service.deleted, ['a']);
      expect(find.byType(MomentViewerPage), findsNothing); // none left
    });
  });

  // ------------------------------------------------------------ the strip ---

  group('the strip on the feed', () {
    late FakeMoments service;
    setUp(() => service = FakeMoments());

    Future<void> pump(
      WidgetTester t, {
      List<PublicUser> friends = const [],
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            momentServiceProvider.overrideWithValue(service),
            currentAccountIdProvider.overrideWithValue('me'),
            chatViewModelProvider.overrideWith(FakeChat.new),
            profileViewModelProvider.overrideWith(_Me.new),
            friendsViewProvider.overrideWithValue(
              FriendsView(friends: friends, hasData: true, isRefreshing: false),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Column(children: [MomentsStrip()])),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
    }

    PublicUser friend(String id, String name) =>
        PublicUser(id: id, username: id, displayName: name);

    testWidgets('with nothing showing it is just your tile, to add one', (
      t,
    ) async {
      await pump(t);
      expect(find.byKey(const ValueKey('moments-mine')), findsOneWidget);
      expect(find.text('Add moment'), findsOneWidget);
      expect(find.byKey(const ValueKey('moments-add')), findsOneWidget);
      expect(
        t.widget<MomentRingFrame>(find.byType(MomentRingFrame)).state,
        MomentRingState.none,
      );
      // Tapping it opens the screen to make one.
      await t.tap(find.byKey(const ValueKey('moments-mine')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentComposerPage), findsOneWidget);
    });

    testWidgets('with one showing, your tile plays it and the + adds another', (
      t,
    ) async {
      service.byUser = {
        'me': [moment('a', user: 'me', caption: 'Mine', views: 2)],
      };
      await pump(t);
      expect(
        t.widget<MomentRingFrame>(find.byType(MomentRingFrame)).state,
        MomentRingState.unseen,
      );
      await t.tap(find.byKey(const ValueKey('moments-mine')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentViewerPage), findsOneWidget);
      expect(find.text('Mine'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('moment-close')));
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await t.tap(find.byKey(const ValueKey('moments-add')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentComposerPage), findsOneWidget);
    });

    testWidgets('friends with a moment follow, unseen ones first', (t) async {
      service.feedAnswer = [
        ring('bo', allSeen: true),
        ring('cy'),
        ring('stranger'), // not a friend: not in the strip
      ];
      await pump(t, friends: [friend('bo', 'Bo B'), friend('cy', 'Cy C')]);
      expect(find.text('Bo B'), findsOneWidget);
      expect(find.text('Cy C'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moments-friend-stranger')),
        findsNothing,
      );
      final cy = t
          .getTopLeft(find.byKey(const ValueKey('moments-friend-cy')))
          .dx;
      final bo = t
          .getTopLeft(find.byKey(const ValueKey('moments-friend-bo')))
          .dx;
      expect(cy, lessThan(bo));
      final mine = t.getTopLeft(find.byKey(const ValueKey('moments-mine'))).dx;
      expect(mine, lessThan(cy));
    });

    testWidgets(
      'tapping a friend plays theirs, and the ring goes quiet after',
      (t) async {
        service
          ..feedAnswer = [ring('cy')]
          ..byUser = {
            'cy': [moment('c1', user: 'cy', caption: 'Cy says hi')],
          };
        await pump(t, friends: [friend('cy', 'Cy C')]);
        expect(
          find.bySemanticsLabel('Has a new moment'),
          findsNothing,
        ); // semantics off
        await t.tap(find.byKey(const ValueKey('moments-friend-cy')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Cy says hi'), findsOneWidget);
        expect(service.seen, ['c1']);

        await t.tap(find.byKey(const ValueKey('moment-close')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        final container = ProviderScope.containerOf(
          t.element(find.byType(MomentsStrip)),
        );
        expect(container.read(momentRingsProvider)['cy']!.allSeen, isTrue);
      },
    );
  });

  // ------------------------------------------------------------- in chat ---

  group('a reply in chat', () {
    testWidgets('shows the moment it was about, with its picture', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              who: 'Bo',
              message: 'Love this',
              side: ChatBubbleSide.incoming,
              quote: ReplyQuoteData(
                author: 'Replied to your moment',
                snippet: 'Sunset',
                thumbnail: _png,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Replied to your moment'), findsOneWidget);
      expect(find.text('Sunset'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-quote-thumb')), findsOneWidget);
    });

    testWidgets('a reply to an Echo is marked with the Echo mark', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              who: 'Bo',
              message: 'Count me in',
              side: ChatBubbleSide.incoming,
              quote: ReplyQuoteData(
                author: 'Answered your Echo',
                snippet: 'Football?',
                icon: EchoIcon(size: 11),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Answered your Echo'), findsOneWidget);
      expect(find.text('Football?'), findsOneWidget);
      expect(find.byType(EchoIcon), findsOneWidget);
    });

    testWidgets('a quote without a picture has no picture', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              who: 'Bo',
              message: 'hi',
              side: ChatBubbleSide.incoming,
              quote: ReplyQuoteData(author: 'Bo', snippet: 'earlier'),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('moment-quote-thumb')), findsNothing);
    });
  });

  final libPath =
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_community_flutter_libs-3.3.2/linux/libisar.so';
  final haveLib = File(libPath).existsSync();

  group('messages that answer a moment', () {
    late Directory dir;
    late Isar isar;
    late FakeSocket socket;
    late StreamController<Map<String, dynamic>> incoming;
    late ProviderContainer c;

    setUpAll(() async {
      if (haveLib) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
      }
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('moment_chat');
      isar = await Isar.open(
        [LocalMessageSchema, LocalChatRoomSchema],
        directory: dir.path,
        name: 'm${DateTime.now().microsecondsSinceEpoch}',
      );
      final service = IsarService.withDb(Future.value(isar))..accountId = 'me';
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      socket = FakeSocket();
      incoming = StreamController<Map<String, dynamic>>.broadcast();
      c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          isarServiceProvider.overrideWithValue(service),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          webSocketEventsProvider.overrideWith((ref) => incoming.stream),
          webSocketServiceProvider.overrideWithValue(socket),
        ],
      );
      c.read(chatViewModelProvider); // starts listening to the socket
    });

    tearDown(() async {
      await incoming.close();
      c.dispose();
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    Future<LocalMessage?> stored(String id) async {
      for (var i = 0; i < 40; i++) {
        final m = await isar.localMessages
            .filter()
            .messageIdEqualTo(id)
            .findFirst();
        if (m != null) return m;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      return null;
    }

    test('what arrives is kept with the moment it was about', () async {
      incoming.add({
        'type': 'message',
        'message_id': 'r1',
        'sender_id': 'bo',
        'recipient_id': 'me',
        'content': 'Love this',
        'status': 'sent',
        'timestamp': '2026-01-01T10:00:00Z',
        'kind': 'text',
        'moment': {
          'id': 'mm1',
          'kind': 'video',
          'caption': 'Swim',
          'thumbnail': _thumb,
        },
      });
      final m = (await stored('r1'))!;
      expect(m.textContent, 'Love this');
      expect(m.momentId, 'mm1');
      expect(m.momentKind, 'video');
      expect(m.momentCaption, 'Swim');
      expect(m.momentThumb, _thumb);
    }, skip: haveLib ? false : 'Isar native library not found');

    test('an ordinary message has no moment', () async {
      incoming.add({
        'type': 'message',
        'message_id': 'r2',
        'sender_id': 'bo',
        'recipient_id': 'me',
        'content': 'hi',
        'status': 'sent',
        'timestamp': '2026-01-01T10:00:00Z',
        'kind': 'text',
      });
      final m = (await stored('r2'))!;
      expect(m.momentId, isNull);
      expect(m.momentThumb, isNull);
    }, skip: haveLib ? false : 'Isar native library not found');

    test(
      'sending one names the moment to the server and keeps what it was',
      () async {
        final about = MomentPreview(
          id: 'mm9',
          kind: MomentKind.photo,
          caption: 'Sunset',
          thumbnail: Uint8List.fromList([0xff, 0xd8, 7]),
        );
        await c
            .read(chatViewModelProvider.notifier)
            .replyToMoment(
              roomId: 'bo_me',
              recipientId: 'bo',
              content: 'Love it',
              about: about,
            );
        final payload = socket.sent.single;
        expect(payload['moment_id'], 'mm9');
        expect(payload['recipient_id'], 'bo');
        expect(payload['content'], 'Love it');
        expect(payload.containsKey('kind'), isFalse); // plain text

        final saved = await isar.localMessages.where().findAll();
        expect(saved.single.momentId, 'mm9');
        expect(saved.single.momentKind, 'photo');
        expect(saved.single.momentCaption, 'Sunset');
        expect(base64Decode(saved.single.momentThumb!), [0xff, 0xd8, 7]);
      },
      skip: haveLib ? false : 'Isar native library not found',
    );

    test(
      'a reply to an Echo names it to the server and keeps its text',
      () async {
        await c
            .read(chatViewModelProvider.notifier)
            .replyToEcho(
              roomId: 'bo_me',
              recipientId: 'bo',
              content: 'Count me in',
              about: const EchoPreview(id: 'e7', text: 'Football?'),
            );
        final payload = socket.sent.single;
        expect(payload['echo_id'], 'e7');
        expect(payload['content'], 'Count me in');
        expect(payload.containsKey('moment_id'), isFalse);
        final saved = (await isar.localMessages.where().findAll()).single;
        expect(saved.echoId, 'e7');
        expect(saved.echoText, 'Football?');
      },
      skip: haveLib ? false : 'Isar native library not found',
    );

    test('an Echo reply that arrives is kept with the Echo', () async {
      incoming.add({
        'type': 'message',
        'message_id': 'e-in',
        'sender_id': 'bo',
        'recipient_id': 'me',
        'content': 'Count me in',
        'status': 'sent',
        'timestamp': '2026-01-01T10:00:00Z',
        'kind': 'text',
        'echo': {'id': 'e7', 'text': 'Football?'},
      });
      final m = (await stored('e-in'))!;
      expect(m.echoId, 'e7');
      expect(m.echoText, 'Football?');
      expect(m.momentId, isNull);
    }, skip: haveLib ? false : 'Isar native library not found');

    test('an ordinary message sends no moment id', () async {
      await c
          .read(chatViewModelProvider.notifier)
          .sendMessage(roomId: 'bo_me', recipientId: 'bo', content: 'hi');
      expect(socket.sent.single.containsKey('moment_id'), isFalse);
    }, skip: haveLib ? false : 'Isar native library not found');
  });
}

class _Failing extends MomentService {
  _Failing() : super(Dio());

  @override
  Future<List<MomentRing>> rings(Iterable<String> userIds) async =>
      throw StateError('offline');
}

class _Me extends ProfileViewModel {
  @override
  FutureOr<Profile?> build() => Profile(
    userId: 'me',
    displayName: 'Alice',
    username: 'alice',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}
