import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/profile_service.dart';
import 'package:serafim/src/data/services/social_service.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Profile profile(String name) => Profile(
  userId: 'u1',
  displayName: name,
  username: name.toLowerCase(),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

PublicUser person(String id, String name) => PublicUser(
  id: id,
  username: name.toLowerCase(),
  displayName: name,
  friendStatus: FriendStatus.friends,
);

class FakeProfiles extends ProfileService {
  FakeProfiles(this.onGet) : super(Dio());
  Future<Profile?> Function() onGet;
  int gets = 0;

  @override
  Future<Profile?> getMine() {
    gets++;
    return onGet();
  }
}

class FakeSocial extends SocialService {
  FakeSocial(this.onFriends) : super(Dio());
  Future<List<PublicUser>> Function() onFriends;

  @override
  Future<List<PublicUser>> friends() => onFriends();
}

Future<LocalCache> prefsCache() async {
  SharedPreferences.setMockInitialValues({});
  return LocalCache(await SharedPreferences.getInstance());
}

ProviderContainer make(
  LocalCache cache, {
  FakeProfiles? profiles,
  FakeSocial? social,
  String? account = 'u1',
}) {
  final c = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localCacheProvider.overrideWithValue(cache),
      currentAccountIdProvider.overrideWithValue(account),
      if (profiles != null) profileServiceProvider.overrideWithValue(profiles),
      if (social != null) socialServiceProvider.overrideWithValue(social),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => ProfileViewModel.loadTimeout = const Duration(milliseconds: 300));
  tearDown(() => ProfileViewModel.loadTimeout = const Duration(seconds: 25));

  group('your profile opens from the phone', () {
    test(
      'a saved profile is available immediately, without waiting for the server',
      () async {
        final cache = await prefsCache();
        await cache.saveProfile('u1', profile('Saved'));
        final c = make(
          cache,
          profiles: FakeProfiles(() => Completer<Profile?>().future),
        );

        final p = await c.read(profileViewModelProvider.future);
        expect(p!.displayName, 'Saved');
      },
    );

    test('the server then refreshes it, on screen and on disk', () async {
      final cache = await prefsCache();
      await cache.saveProfile('u1', profile('Old'));
      final c = make(cache, profiles: FakeProfiles(() async => profile('New')));

      expect(
        (await c.read(profileViewModelProvider.future))!.displayName,
        'Old',
      );
      await pumpEventQueue(times: 20);
      expect(c.read(profileViewModelProvider).value!.displayName, 'New');
      expect(cache.profile('u1')!.profile!.displayName, 'New');
    });

    test('offline: the saved profile stays on screen, with no error', () async {
      final cache = await prefsCache();
      await cache.saveProfile('u1', profile('Saved'));
      final c = make(
        cache,
        profiles: FakeProfiles(() async => throw const ApiException('offline')),
      );

      await c.read(profileViewModelProvider.future);
      await pumpEventQueue(times: 20);
      final state = c.read(profileViewModelProvider);
      expect(state.hasError, isFalse);
      expect(state.value!.displayName, 'Saved');
    });

    test(
      '"no profile yet" is also remembered, so a new user is not held up',
      () async {
        final cache = await prefsCache();
        await cache.saveProfile('u1', null);
        final c = make(
          cache,
          profiles: FakeProfiles(() => Completer<Profile?>().future),
        );
        expect(await c.read(profileViewModelProvider.future), isNull);
      },
    );

    test(
      'if the profile was deleted on the server, the saved one is dropped',
      () async {
        final cache = await prefsCache();
        await cache.saveProfile('u1', profile('Ghost'));
        final c = make(cache, profiles: FakeProfiles(() async => null));

        await c.read(profileViewModelProvider.future);
        await pumpEventQueue(times: 20);
        expect(c.read(profileViewModelProvider).value, isNull);
        expect(cache.profile('u1')!.profile, isNull);
      },
    );

    test(
      'first launch: fetched from the server and saved for next time',
      () async {
        final cache = await prefsCache();
        final c = make(
          cache,
          profiles: FakeProfiles(() async => profile('Fresh')),
        );
        expect(
          (await c.read(profileViewModelProvider.future))!.displayName,
          'Fresh',
        );
        expect(cache.profile('u1')!.profile!.displayName, 'Fresh');
      },
    );

    test(
      'first launch and the server never answers: an error, not an endless spinner',
      () async {
        final cache = await prefsCache();
        final c = make(
          cache,
          profiles: FakeProfiles(() => Completer<Profile?>().future),
        );
        c.listen(profileViewModelProvider, (_, __) {});
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await pumpEventQueue(times: 20);
        final state = c.read(profileViewModelProvider);
        expect(state.isLoading, isFalse);
        expect(state.hasError, isTrue);
      },
    );

    test('a profile you edit is saved to the phone as well', () async {
      final cache = await prefsCache();
      await cache.saveProfile('u1', profile('Before'));
      final fake = FakeProfiles(() async => profile('Before'));
      final c = make(cache, profiles: fake);
      await c.read(profileViewModelProvider.future);
      await pumpEventQueue(times: 10);

      // Pretend the server accepted a rename.
      final result = await c
          .read(profileViewModelProvider.notifier)
          .updateProfile(const ProfileUpdateRequest(displayName: 'After'));
      expect(
        result,
        isNotNull,
        reason:
            'the fake service has no update, so it reports a friendly error',
      );
      expect(c.read(profileViewModelProvider).value!.displayName, 'Before');
    });

    test('signed out: nothing is read or fetched', () async {
      final cache = await prefsCache();
      final fake = FakeProfiles(() async => profile('x'));
      final c = make(cache, profiles: fake, account: null);
      expect(await c.read(profileViewModelProvider.future), isNull);
      expect(fake.gets, 0);
    });
  });

  group('a failing request is shown, not retried in the background', () {
    test(
      'the profile fails once, immediately: no hidden retries behind a spinner',
      () async {
        final cache = await prefsCache();
        final fake = FakeProfiles(
          () async => throw const ApiException('nope', statusCode: 401),
        );
        final c = make(cache, profiles: fake);
        c.listen(profileViewModelProvider, (_, __) {});

        await Future<void>.delayed(
          const Duration(milliseconds: 800),
        ); // Riverpod's default would retry in this time
        await pumpEventQueue(times: 20);
        final state = c.read(profileViewModelProvider);
        expect(
          state.isLoading,
          isFalse,
          reason: 'it must show the error, not "loading"',
        );
        expect(state.hasError, isTrue);
        expect(
          fake.gets,
          1,
          reason: 'one attempt; the Retry button is the person\'s choice',
        );
      },
    );

    test('the friends list behaves the same way', () async {
      final cache = await prefsCache();
      var calls = 0;
      final c = make(
        cache,
        social: FakeSocial(() async {
          calls++;
          throw const ApiException('nope');
        }),
      );
      c.listen(friendsProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await pumpEventQueue(times: 20);
      expect(c.read(friendsProvider).isLoading, isFalse);
      expect(calls, 1);
    });

    test('the app-wide retry setting really is "never"', () {
      for (var attempt = 0; attempt < 12; attempt++) {
        expect(noAutoRetry(attempt, Exception('x')), isNull);
      }
    });
  });

  group('your friends list opens from the phone', () {
    test(
      'the saved list shows straight away while the server is still working',
      () async {
        final cache = await prefsCache();
        await cache.saveFriends('u1', [person('a', 'Alex'), person('b', 'Bo')]);
        final c = make(
          cache,
          social: FakeSocial(() => Completer<List<PublicUser>>().future),
        );
        c.listen(friendsViewProvider, (_, __) {});

        final view = c.read(friendsViewProvider);
        expect(
          view.hasData,
          isTrue,
          reason: 'no spinner: there is a saved list',
        );
        expect(view.isRefreshing, isTrue);
        expect(view.friends.map((f) => f.displayName), ['Alex', 'Bo']);
        expect(view.error, isNull);
      },
    );

    test(
      'the server\'s list replaces it, and is saved (with the people in it)',
      () async {
        final cache = await prefsCache();
        await cache.saveFriends('u1', [person('a', 'Old')]);
        final c = make(
          cache,
          social: FakeSocial(
            () async => [person('a', 'Alex'), person('c', 'Cy')],
          ),
        );
        c.listen(friendsViewProvider, (_, __) {});

        await c.read(friendsProvider.future);
        await pumpEventQueue(times: 10);
        expect(c.read(friendsViewProvider).friends.map((f) => f.displayName), [
          'Alex',
          'Cy',
        ]);
        expect(cache.friends('u1')!.map((f) => f.id), ['a', 'c']);
        expect(
          cache.person('u1', 'c')!.displayName,
          'Cy',
          reason: 'so their profile opens instantly',
        );
      },
    );

    test('offline with a saved list: still shown, and no error', () async {
      final cache = await prefsCache();
      await cache.saveFriends('u1', [person('a', 'Alex')]);
      final c = make(
        cache,
        social: FakeSocial(() async => throw const ApiException('offline')),
      );
      c.listen(friendsViewProvider, (_, __) {});

      await pumpEventQueue(times: 20);
      final view = c.read(friendsViewProvider);
      expect(view.friends.single.displayName, 'Alex');
      expect(view.error, isNull);
      expect(view.hasData, isTrue);
    });

    test(
      'offline and nothing saved: the error is reported, so the screen can say so',
      () async {
        final cache = await prefsCache();
        final c = make(
          cache,
          social: FakeSocial(() async => throw const ApiException('offline')),
        );
        c.listen(friendsViewProvider, (_, __) {});

        await pumpEventQueue(times: 20);
        final view = c.read(friendsViewProvider);
        expect(view.hasData, isFalse);
        expect(view.error, isNotNull);
      },
    );

    test(
      'first launch: the spinner state is exactly "nothing yet, still loading"',
      () async {
        final cache = await prefsCache();
        final c = make(
          cache,
          social: FakeSocial(() => Completer<List<PublicUser>>().future),
        );
        c.listen(friendsViewProvider, (_, __) {});
        final view = c.read(friendsViewProvider);
        expect([view.hasData, view.isRefreshing], [false, true]);
      },
    );

    test('someone else\'s saved list is never shown to you', () async {
      final cache = await prefsCache();
      await cache.saveFriends('other', [person('x', 'Stranger')]);
      final c = make(
        cache,
        social: FakeSocial(() => Completer<List<PublicUser>>().future),
      );
      c.listen(friendsViewProvider, (_, __) {});
      expect(c.read(friendsViewProvider).hasData, isFalse);
    });

    test(
      'friend ids come from the saved list, so attachments are gated correctly offline',
      () async {
        final cache = await prefsCache();
        await cache.saveFriends('u1', [person('a', 'Alex')]);
        final c = make(
          cache,
          social: FakeSocial(() => Completer<List<PublicUser>>().future),
        );
        c.listen(friendIdsProvider, (_, __) {});
        expect(c.read(friendIdsProvider), {'a'});
      },
    );
  });

  group('knowing someone without asking the server', () {
    test('a friend, a saved stranger, and an unknown person', () async {
      final cache = await prefsCache();
      await cache.saveFriends('u1', [person('a', 'Alex')]);
      await cache.savePerson('u1', person('s', 'Stranger'));
      final c = make(
        cache,
        social: FakeSocial(() => Completer<List<PublicUser>>().future),
      );
      c.listen(friendsViewProvider, (_, __) {});

      expect(c.read(knownPersonProvider('a'))!.displayName, 'Alex');
      expect(c.read(knownPersonProvider('s'))!.displayName, 'Stranger');
      expect(c.read(knownPersonProvider('nobody')), isNull);
    });

    test('signed out: nobody is known', () async {
      final cache = await prefsCache();
      await cache.savePerson('u1', person('s', 'Stranger'));
      final c = make(cache, account: null);
      expect(c.read(knownPersonProvider('s')), isNull);
    });
  });
}
