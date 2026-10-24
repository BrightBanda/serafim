import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/chat_filter.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/wings_service.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/view/wings_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/wings_providers.dart';
import 'package:serafim/src/utils/wing_toggle.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

PublicUser _p(String id, {FriendStatus status = FriendStatus.friends}) =>
    PublicUser(
      id: id,
      username: id,
      displayName: 'Person $id',
      friendStatus: status,
    );

/// A server that keeps the list, like the real one.
class _FakeWings extends WingsService {
  _FakeWings([List<PublicUser> start = const []])
    : _list = [...start],
      super(Dio());

  final List<PublicUser> _list;
  Object? failWith;
  int calls = 0;

  @override
  Future<List<PublicUser>> list() async => [..._list];

  @override
  Future<List<PublicUser>> add(String userId) async {
    calls++;
    if (failWith != null) throw failWith!;
    if (!_list.any((w) => w.id == userId)) _list.add(_p(userId));
    return [..._list];
  }

  @override
  Future<List<PublicUser>> remove(String userId) async {
    calls++;
    if (failWith != null) throw failWith!;
    _list.removeWhere((w) => w.id == userId);
    return [..._list];
  }
}

Future<({ProviderContainer c, _FakeWings server, LocalCache cache})> make({
  List<PublicUser> onServer = const [],
  List<PublicUser>? saved,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final cache = LocalCache(prefs);
  if (saved != null) await cache.saveWings('me', saved);
  final server = _FakeWings(onServer);
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localCacheProvider.overrideWithValue(cache),
      currentAccountIdProvider.overrideWithValue('me'),
      wingsServiceProvider.overrideWithValue(server),
    ],
  );
  addTearDown(c.dispose);
  return (c: c, server: server, cache: cache);
}

void main() {
  group('the list', () {
    test(
      'opens at once from the saved copy, then follows the server',
      () async {
        final t = await make(saved: [_p('a')], onServer: [_p('a'), _p('b')]);
        expect(t.c.read(wingsProvider).map((w) => w.id), [
          'a',
        ], reason: 'instant');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(t.c.read(wingsProvider).map((w) => w.id), ['a', 'b']);
        expect(t.cache.wings('me')!.map((w) => w.id), [
          'a',
          'b',
        ], reason: 'saved');
      },
    );

    test('adding shows at once and settles on the server answer', () async {
      final t = await make();
      final n = t.c.read(wingsProvider.notifier);
      final future = n.add(_p('a'));
      expect(t.c.read(wingIdsProvider), {
        'a',
      }, reason: 'before the server answers');
      expect(await future, isNull);
      expect(t.c.read(isWingProvider('a')), isTrue);
      expect(t.c.read(isWingProvider('b')), isFalse);
    });

    test('a refusal puts the list back and says why', () async {
      final t = await make();
      t.server.failWith = const ApiException('Only friends can be your Wings.');
      final error = await t.c.read(wingsProvider.notifier).add(_p('a'));
      expect(error, contains('friends'));
      expect(t.c.read(wingsProvider), isEmpty);
    });

    test('six at most, checked before asking the server', () async {
      final t = await make(saved: [for (var i = 0; i < 6; i++) _p('w$i')]);
      final n = t.c.read(wingsProvider.notifier);
      final error = await n.add(_p('seventh'));
      expect(error, contains('6'));
      expect(t.server.calls, 0, reason: 'no request for a sure refusal');
      expect(t.c.read(wingsProvider), hasLength(6));
    });

    test('removing, and removing someone who was never a wing', () async {
      final t = await make(
        saved: [_p('a'), _p('b')],
        onServer: [_p('a'), _p('b')],
      );
      final n = t.c.read(wingsProvider.notifier);
      expect(await n.remove('a'), isNull);
      expect(t.c.read(wingIdsProvider), {'b'});
      expect(await n.remove('zzz'), isNull);
    });

    test('adding the same friend twice does nothing', () async {
      final t = await make();
      final n = t.c.read(wingsProvider.notifier);
      await n.add(_p('a'));
      final calls = t.server.calls;
      expect(await n.add(_p('a')), isNull);
      expect(t.server.calls, calls);
      expect(t.c.read(wingsProvider), hasLength(1));
    });
  });

  group('the Whispers filter', () {
    List<ChatEntry> entries() => [
      ChatEntry('a', _p('a')),
      ChatEntry('b', _p('b')),
    ];

    test('keeps only chats with your Wings', () {
      final kept = applyChatFilter(
        entries(),
        ChatFilter.wings,
        const {},
        'me',
        wingIds: {'b'},
      );
      expect(kept.map((e) => e.id), ['b']);
    });

    test('no Wings: nothing, and it is a built-in filter', () {
      expect(
        applyChatFilter(entries(), ChatFilter.wings, const {}, 'me'),
        isEmpty,
      );
      expect(ChatFilter.builtIns, contains(ChatFilter.wings));
    });
  });

  group('who gets a banner', () {
    test('banners on: everyone', () {
      expect(
        bannerAllowed(
          bannersOn: true,
          fromWing: false,
          wingsBreakThrough: true,
        ),
        isTrue,
      );
    });

    test('banners off: nobody, except Wings, when allowed', () {
      expect(
        bannerAllowed(
          bannersOn: false,
          fromWing: false,
          wingsBreakThrough: true,
        ),
        isFalse,
      );
      expect(
        bannerAllowed(
          bannersOn: false,
          fromWing: true,
          wingsBreakThrough: true,
        ),
        isTrue,
      );
      expect(
        bannerAllowed(
          bannersOn: false,
          fromWing: true,
          wingsBreakThrough: false,
        ),
        isFalse,
      );
    });
  });

  group('the page', () {
    Future<_FakeWings> open(
      WidgetTester t, {
      List<PublicUser> wings = const [],
      List<PublicUser> friends = const [],
    }) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final made = await make(saved: wings, onServer: wings);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(
                await SharedPreferences.getInstance(),
              ),
              localCacheProvider.overrideWithValue(made.cache),
              currentAccountIdProvider.overrideWithValue('me'),
              wingsServiceProvider.overrideWithValue(made.server),
              friendsProvider.overrideWith((ref) => friends),
            ],
          ),
          child: const MaterialApp(home: WingsPage()),
        ),
      );
      await t.pump();
      return made.server;
    }

    testWidgets('six places: filled ones and empty ones', (t) async {
      await open(t, wings: [_p('a'), _p('b')]);
      expect(find.text('2 of 6'), findsOneWidget);
      expect(find.byKey(const ValueKey('wing-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('wing-empty-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('wing-empty-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('wing-empty-1')), findsNothing);
    });

    testWidgets('an empty place lets you pick a friend', (t) async {
      final server = await open(t, friends: [_p('x'), _p('y')]);
      await t.tap(find.byKey(const ValueKey('wing-empty-0')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-x')), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('wing-search')), 'Person y');
      await t.pump();
      expect(find.byKey(const ValueKey('pick-x')), findsNothing);

      await t.tap(find.byKey(const ValueKey('pick-y')));
      await t.pumpAndSettle();
      expect(server.calls, 1);
      expect(find.byKey(const ValueKey('wing-y')), findsOneWidget);
    });

    testWidgets('a friend who is already a wing is not offered again', (
      t,
    ) async {
      await open(t, wings: [_p('x')], friends: [_p('x'), _p('y')]);
      await t.tap(find.byKey(const ValueKey('wing-empty-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-x')), findsNothing);
      expect(find.byKey(const ValueKey('pick-y')), findsOneWidget);
    });

    testWidgets('tapping a wing asks, then removes', (t) async {
      final server = await open(t, wings: [_p('a')]);
      await t.tap(find.byKey(const ValueKey('wing-a')));
      await t.pumpAndSettle();
      expect(find.textContaining('off your Wings?'), findsOneWidget);
      await t.tap(find.text('Remove'));
      await t.pumpAndSettle();
      expect(server.calls, 1);
      expect(find.byKey(const ValueKey('wing-a')), findsNothing);
      expect(find.text('0 of 6'), findsOneWidget);
    });
  });

  group('on a friend\'s profile', () {
    Future<void> show(
      WidgetTester t,
      PublicUser user,
      _FakeWings server,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            localCacheProvider.overrideWithValue(LocalCache(prefs)),
            currentAccountIdProvider.overrideWithValue('me'),
            wingsServiceProvider.overrideWithValue(server),
          ],
          child: MaterialApp(
            home: Scaffold(body: WingToggle(user: user)),
          ),
        ),
      );
      await t.pump();
    }

    testWidgets('a friend can be added and removed', (t) async {
      final server = _FakeWings();
      await show(t, _p('a'), server);
      expect(find.text('Add to Wings'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('wing-toggle')));
      await t.pumpAndSettle();
      expect(find.text('Remove from Wings'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('wing-toggle')));
      await t.pumpAndSettle();
      expect(find.text('Add to Wings'), findsOneWidget);
    });

    testWidgets('someone who is not a friend gets no button', (t) async {
      await show(t, _p('a', status: FriendStatus.none), _FakeWings());
      expect(find.byKey(const ValueKey('wing-toggle')), findsNothing);
    });
  });
}
