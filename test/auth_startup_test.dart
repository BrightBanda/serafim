import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class Rig {
  Rig(this.container, this.store, this.users, this.cache);
  final ProviderContainer container;
  final FakeSessionStore store;
  final FakeUserService users;
  final LocalCache cache;

  AuthState get state => container.read(authViewModelProvider);
}

/// Builds the app's auth layer on fakes. [saved] is the account copy already on
/// the phone from the last run; [session] is the stored login.
Future<Rig> rig({
  bool session = true,
  AppUser? saved,
  required Future<AppUser> Function() sync,
  Object? restoreError,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final cache = LocalCache(prefs);
  if (saved != null) await cache.saveUser(saved);

  final store = FakeSessionStore(session ? fakeSession() : null)
    ..restoreError = restoreError;
  final users = FakeUserService(sync);

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sessionStoreProvider.overrideWithValue(store),
      userServiceProvider.overrideWithValue(users),
      authServiceProvider.overrideWithValue(FakeAuthService()),
    ],
  );
  addTearDown(container.dispose);
  return Rig(container, store, users, cache);
}

/// Starts the view model and lets everything that can settle, settle.
Future<void> start(Rig r) async {
  r.container.listen(authViewModelProvider, (_, __) {}, fireImmediately: true);
  await pumpEventQueue(times: 40);
}

ApiException status(int code, [String message = 'x']) =>
    ApiException(message, statusCode: code);

void main() {
  setUp(
    () => AuthViewModel.blockingTimeout = const Duration(milliseconds: 300),
  );
  tearDown(() => AuthViewModel.blockingTimeout = const Duration(seconds: 25));

  group('signed out', () {
    test(
      'no stored login: straight to the sign-in screen, no server call',
      () async {
        final r = await rig(session: false, sync: () async => fakeUser());
        await start(r);
        expect(r.state.status, AuthStatus.unauthenticated);
        expect(r.users.syncCalls, 0);
      },
    );

    test(
      'a failure reading the keystore still ends on a real screen, not a spinner',
      () async {
        final r = await rig(
          restoreError: StateError('keystore exploded'),
          sync: () async => fakeUser(),
        );
        await start(r);
        expect(r.state.status, AuthStatus.unauthenticated);
      },
    );
  });

  group('opening instantly from the saved copy', () {
    test('the app opens before the server has answered', () async {
      final neverAnswers = Completer<AppUser>();
      final r = await rig(
        saved: fakeUser(email: 'saved@example.com'),
        sync: () => neverAnswers.future,
      );
      await start(r);

      expect(r.state.status, AuthStatus.authenticated);
      expect(r.state.user!.email, 'saved@example.com');
      expect(
        r.users.syncCalls,
        1,
        reason: 'the server is still asked, in the background',
      );
    });

    test(
      'when the server answers, the saved copy is refreshed and updated',
      () async {
        final answer = Completer<AppUser>();
        final r = await rig(
          saved: fakeUser(email: 'old@example.com'),
          sync: () => answer.future,
        );
        await start(r);
        expect(r.state.user!.email, 'old@example.com');

        answer.complete(fakeUser(email: 'new@example.com'));
        await pumpEventQueue(times: 20);
        expect(r.state.status, AuthStatus.authenticated);
        expect(r.state.user!.email, 'new@example.com');
        expect(
          r.cache.user('u1')!.email,
          'new@example.com',
          reason: 'next launch opens on the new copy',
        );
      },
    );

    test(
      'offline: the app stays open on the saved copy and the login is kept',
      () async {
        final r = await rig(
          saved: fakeUser(),
          sync: () async => throw const ApiException('offline'),
        );
        await start(r);
        expect(r.state.status, AuthStatus.authenticated);
        expect(r.store.current, isNotNull);
        expect(r.store.clearCount, 0);
      },
    );

    test('a server error (500) is not a reason to sign you out', () async {
      final r = await rig(
        saved: fakeUser(),
        sync: () async => throw status(500, 'boom'),
      );
      await start(r);
      expect(r.state.status, AuthStatus.authenticated);
      expect(r.store.clearCount, 0);
    });

    test('a slow server does not hold the app up either', () async {
      final r = await rig(
        saved: fakeUser(),
        sync: () => Completer<AppUser>().future, // never answers
      );
      await start(r);
      await Future<void>.delayed(
        const Duration(milliseconds: 500),
      ); // past the timeout
      await pumpEventQueue(times: 20);
      expect(r.state.status, AuthStatus.authenticated);
    });
  });

  group('the account was deleted on the server', () {
    test(
      'with a saved copy: the app opens, then signs out with a clear message',
      () async {
        final r = await rig(
          saved: fakeUser(),
          sync: () async => throw status(
            401,
            'This account no longer exists. Please sign in again.',
          ),
        );
        await start(r);

        expect(r.state.status, AuthStatus.unauthenticated);
        expect(r.state.notice, contains('no longer exists'));
        expect(
          r.store.current,
          isNull,
          reason: 'the dead login is thrown away',
        );
        expect(
          r.cache.user('u1'),
          isNull,
          reason: "and so is the account's saved data",
        );
      },
    );

    test(
      'with no saved copy: signed out with a message, never an endless spinner',
      () async {
        final r = await rig(
          sync: () async => throw status(
            401,
            'This account no longer exists. Please sign in again.',
          ),
        );
        await start(r);
        expect(r.state.status, AuthStatus.unauthenticated);
        expect(r.state.notice, contains('no longer exists'));
        expect(r.store.current, isNull);
      },
    );

    test('a generic rejection explains that the session ended', () async {
      final r = await rig(
        saved: fakeUser(),
        sync: () async => throw status(403),
      );
      await start(r);
      expect(r.state.status, AuthStatus.unauthenticated);
      expect(r.state.notice, 'Your session has ended. Please sign in again.');
    });

    test('the notice is shown once and can be cleared', () async {
      final r = await rig(
        saved: fakeUser(),
        sync: () async => throw status(401),
      );
      await start(r);
      expect(r.state.notice, isNotNull);
      r.container.read(authViewModelProvider.notifier).clearNotice();
      expect(r.state.notice, isNull);
      expect(r.state.status, AuthStatus.unauthenticated);
    });
  });

  group('first launch with no saved copy (must wait, but never forever)', () {
    test('success: opens, and saves a copy for next time', () async {
      final r = await rig(
        sync: () async => fakeUser(email: 'first@example.com'),
      );
      await start(r);
      expect(r.state.status, AuthStatus.authenticated);
      expect(r.cache.user('u1')!.email, 'first@example.com');
    });

    test(
      'the server never answers: a retry screen after the timeout, not a spinner',
      () async {
        final r = await rig(sync: () => Completer<AppUser>().future);
        await start(r);
        expect(r.state.status, AuthStatus.unknown, reason: 'still waiting');

        await Future<void>.delayed(const Duration(milliseconds: 500));
        await pumpEventQueue(times: 20);
        expect(r.state.status, AuthStatus.backendUnavailable);
        expect(
          r.store.current,
          isNotNull,
          reason: 'the login is kept for the retry',
        );
      },
    );

    test(
      'an unexpected crash while reading the answer also ends on a real screen',
      () async {
        final r = await rig(sync: () async => throw TypeError());
        await start(r);
        expect(r.state.status, AuthStatus.backendUnavailable);
      },
    );

    test(
      'offline: a retry screen, and retrying works once the network is back',
      () async {
        var online = false;
        final r = await rig(
          sync: () async => online
              ? fakeUser()
              : throw const ApiException("Can't reach the server."),
        );
        await start(r);
        expect(r.state.status, AuthStatus.backendUnavailable);

        online = true;
        await r.container
            .read(authViewModelProvider.notifier)
            .retryBackendSync();
        await pumpEventQueue(times: 20);
        expect(r.state.status, AuthStatus.authenticated);
        expect(r.state.isBusy, isFalse);
      },
    );

    test('the retry itself can never leave the busy flag stuck on', () async {
      final r = await rig(sync: () async => throw TypeError());
      await start(r);
      await r.container.read(authViewModelProvider.notifier).retryBackendSync();
      await pumpEventQueue(times: 20);
      expect(r.state.isBusy, isFalse);
    });
  });

  group('the login ending while the app is open', () {
    test(
      'the interceptor giving up signs you out with a notice and forgets the data',
      () async {
        final r = await rig(saved: fakeUser(), sync: () async => fakeUser());
        await start(r);
        expect(r.state.status, AuthStatus.authenticated);

        await r.store
            .clear(); // what the interceptor does when the login is dead
        await pumpEventQueue(times: 10);
        expect(r.state.status, AuthStatus.unauthenticated);
        expect(r.state.notice, contains('session has ended'));
        expect(r.cache.user('u1'), isNull);
      },
    );

    test('a sign-out you ask for shows no "session ended" notice', () async {
      final r = await rig(saved: fakeUser(), sync: () async => fakeUser());
      await start(r);
      await r.container.read(authViewModelProvider.notifier).signOut();
      await pumpEventQueue(times: 10);
      expect(r.state.status, AuthStatus.unauthenticated);
      expect(r.state.notice, isNull);
      expect(
        r.cache.user('u1'),
        isNull,
        reason: 'the next person on this phone sees nothing of yours',
      );
    });
  });
}
