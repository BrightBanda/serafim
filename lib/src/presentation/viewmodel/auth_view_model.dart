import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/auth_session.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/data/services/session_store.dart';
import 'package:serafim/src/data/services/user_service.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';

/// Marks "leave this field alone" in `copyWith`, so `null` can mean "clear".
const Object _keep = Object();

enum AuthStatus {
  /// Startup: we have not yet read the keystore, so we do not know.
  unknown,
  unauthenticated,

  /// Signed up, but Supabase is waiting on an email click before issuing
  /// tokens. Not authenticated, but not a plain signed-out state either.
  awaitingEmailConfirmation,

  /// We hold a valid Supabase session but the Serafim backend did not answer.
  /// Distinct from [unauthenticated]: the user is signed in, we just cannot
  /// load their app-side row. Dumping them on the sign-up screen here would
  /// invite a second registration that Supabase then rejects as a duplicate.
  backendUnavailable,
  authenticated,
}

/// Everything the UI needs to know about who is signed in.
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.isBusy = false,
    this.notice,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);

  final AuthStatus status;

  /// The application user row, populated from `POST /auth/sync`.
  final AppUser? user;

  /// True while a sign-in, sign-up, or sign-out is in flight.
  final bool isBusy;

  /// Something to tell the person once, on the sign-in screen — e.g. that
  /// their session ended because the account no longer exists.
  final String? notice;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    bool? isBusy,
    Object? notice = _keep,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isBusy: isBusy ?? this.isBusy,
      notice: identical(notice, _keep) ? this.notice : notice as String?,
    );
  }
}

/// Owns the session lifecycle: restore, sign up, sign in, sign out.
///
/// All auth logic lives here rather than in a widget. The screens only read
/// [AuthState] and call these methods. Failures are thrown as [ApiException]
/// so the caller decides how to present them — a form shows the message
/// inline, a background restore swallows it.
class AuthViewModel extends Notifier<AuthState> {
  AuthService get _auth => ref.read(authServiceProvider);
  UserService get _users => ref.read(userServiceProvider);
  SessionStore get _store => ref.read(sessionStoreProvider);

  @override
  AuthState build() {
    // The interceptor writes to the store directly when it refreshes or gives
    // up. Listening keeps this view model honest about a sign-out it did not
    // initiate.
    final subscription = _store.changes.listen(_onSessionChanged);
    ref.onDispose(subscription.cancel);

    // build() is synchronous, so the keystore read is kicked off just after.
    // Whatever happens, startup must end in a real state: a spinner that never
    // resolves is the worst outcome, so anything unexpected means "signed out".
    unawaited(
      _restore()
          .catchError((Object _) {
            if (ref.mounted && state.status == AuthStatus.unknown) {
              state = const AuthState.unauthenticated();
            }
          })
          .whenComplete(() {
            if (ref.mounted && state.status == AuthStatus.unknown) {
              state = const AuthState.unauthenticated();
            }
          }),
    );

    return const AuthState.unknown();
  }

  /// How long startup waits for the server when there is no saved copy to
  /// open with. Past this, the retry screen appears instead of a spinner.
  @visibleForTesting
  static Duration blockingTimeout = const Duration(seconds: 25);

  bool _signingOut = false;

  /// Opens the app as quickly as possible.
  ///
  /// If this phone already has a saved copy of the account (from the last
  /// time it was open), the app starts on that immediately — no waiting for
  /// the server — and the server is asked in the background whether the
  /// session is still good. Only a first launch has to wait.
  Future<void> _restore() async {
    final session = await _store.restore();
    if (!ref.mounted) return;

    if (session == null) {
      state = const AuthState.unauthenticated();
      return;
    }

    final saved = ref.read(localCacheProvider).user(session.userId);
    if (saved != null) {
      state = AuthState(status: AuthStatus.authenticated, user: saved);
      unawaited(_confirmInBackground());
      return;
    }

    await _confirmBlocking();
  }

  /// No saved copy: ask the server, but never wait forever.
  Future<void> _confirmBlocking() async {
    try {
      final user = await _users.sync().timeout(blockingTimeout);
      if (!ref.mounted) return;
      await ref.read(localCacheProvider).saveUser(user);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (error) {
      if (!ref.mounted) return;
      if (_sessionIsDead(error)) {
        await _endSession(_sessionEndedMessage(error));
      } else {
        // Offline, slow, or the server is having a bad day. The session is
        // still good, so keep it and offer a retry.
        state = const AuthState(status: AuthStatus.backendUnavailable);
      }
    }
  }

  /// Saved copy shown; now check it with the server without blocking anyone.
  Future<void> _confirmInBackground() async {
    try {
      final user = await _users.sync().timeout(blockingTimeout);
      if (!ref.mounted) return;
      await ref.read(localCacheProvider).saveUser(user);
      if (state.status == AuthStatus.authenticated) {
        state = state.copyWith(user: user);
      }
    } catch (error) {
      if (!ref.mounted) return;
      // Offline or a server hiccup: carry on with the saved copy, like a
      // messaging app does. Only a definite "no" ends the session.
      if (_sessionIsDead(error)) {
        await _endSession(_sessionEndedMessage(error));
      }
    }
  }

  /// A definite answer that this login cannot be used any more: the server
  /// rejected the token (even after a refresh) or said the account is gone.
  /// Being offline, timing out or a 500 are *not* this.
  static bool _sessionIsDead(Object error) =>
      error is ApiException &&
      (error.statusCode == 401 || error.statusCode == 403);

  static String _sessionEndedMessage(Object error) {
    final text = error is ApiException ? error.message : '';
    return text.toLowerCase().contains('no longer exists')
        ? text
        : 'Your session has ended. Please sign in again.';
  }

  /// Signs out because the server says this login is no longer valid, and
  /// forgets the saved copy of the account.
  Future<void> _endSession(String notice) async {
    final account = state.user?.id ?? _store.current?.userId;
    await _store.clear();
    if (account != null) await ref.read(localCacheProvider).clear(account);
    if (!ref.mounted) return;
    state = AuthState(status: AuthStatus.unauthenticated, notice: notice);
  }

  void clearNotice() {
    if (state.notice != null) state = state.copyWith(notice: null);
  }

  /// Re-attempts the startup sync. Wired to the retry button shown for
  /// [AuthStatus.backendUnavailable].
  Future<void> retryBackendSync() async {
    state = state.copyWith(isBusy: true);
    try {
      await _restore();
    } finally {
      if (ref.mounted && state.isBusy) state = state.copyWith(isBusy: false);
    }
  }

  /// Registers with Supabase, then establishes the session if one came back.
  ///
  /// Throws [ApiException] on failure.
  Future<void> signUp({required String email, required String password}) async {
    state = state.copyWith(isBusy: true);
    try {
      final result = await _auth.signUp(email: email, password: password);

      if (result.needsEmailConfirmation) {
        state = const AuthState(status: AuthStatus.awaitingEmailConfirmation);
        return;
      }
      await _establish(result.session!);
    } finally {
      if (ref.mounted && state.isBusy) state = state.copyWith(isBusy: false);
    }
  }

  /// Throws [ApiException] on failure.
  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isBusy: true);
    try {
      await _establish(await _auth.signIn(email: email, password: password));
    } finally {
      if (ref.mounted && state.isBusy) state = state.copyWith(isBusy: false);
    }
  }

  /// Signs in (or up — Google makes no distinction) with a Google account.
  ///
  /// Returns false if the user dismissed the account picker, true once
  /// signed in. Throws [ApiException] on failure.
  Future<bool> signInWithGoogle() async {
    if (state.isBusy) return false;
    state = state.copyWith(isBusy: true);
    try {
      final String idToken;
      try {
        idToken = await ref.read(googleAuthServiceProvider).signIn();
      } on GoogleSignInCancelled {
        return false;
      }
      await _establish(await _auth.signInWithGoogleIdToken(idToken));
      return true;
    } finally {
      if (ref.mounted && state.isBusy) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> signOut() async {
    final session = _store.current;
    final account = state.user?.id ?? session?.userId;
    _signingOut =
        true; // A sign-out you asked for needs no "session ended" notice.
    state = state.copyWith(isBusy: true);

    // Stop pushes to this phone while we can still authenticate the request.
    await ref.read(pushRegistrarProvider).unregisterThisDevice();
    await ref.read(googleAuthServiceProvider).signOut();

    if (session != null) {
      await _auth.signOut(session.accessToken);
    }
    // Clearing emits on SessionStore.changes, which drives the state below,
    // but set it here too so the transition is immediate rather than waiting
    // on a microtask.
    await _store.clear();
    // The next person to use this phone must not see this account's data.
    if (account != null) await ref.read(localCacheProvider).clear(account);
    _signingOut = false;
    if (!ref.mounted) return;
    state = const AuthState.unauthenticated();
  }

  /// Persists the session and pulls our own user row into state.
  ///
  /// The order matters: the session must be in the store before `/auth/sync`
  /// is called, because the interceptor reads the token from there.
  Future<void> _establish(AuthSession session) async {
    await _store.save(session);

    try {
      final user = await _users.sync();
      if (!ref.mounted) return;
      await ref.read(localCacheProvider).saveUser(user);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException catch (error) {
      // The server rejected a login it has only just issued: the account is
      // unusable (for instance it was deleted). Don't keep a session that can
      // never work.
      if (_sessionIsDead(error)) {
        await _store.clear();
        rethrow;
      }
      // The Supabase account now exists but our own row does not. Say which
      // server failed — "could not reach the server" is unhelpful when the
      // flow just talked to two of them. The session stays saved, so a retry
      // or a relaunch picks up where this left off rather than attempting a
      // duplicate registration.
      if (error.statusCode == null) {
        state = const AuthState(status: AuthStatus.backendUnavailable);
        throw const ApiException(
          "You're signed in, but Serafim couldn't reach its server. Check "
          "your internet connection and try again. You won't need to sign up "
          'twice.',
        );
      }
      rethrow;
    }
  }

  /// The session was cleared by something other than a sign-out you asked for
  /// (the interceptor found the login revoked or the account gone).
  void _onSessionChanged(AuthSession? session) {
    if (session != null || !state.isAuthenticated || _signingOut) return;
    final account = state.user?.id;
    if (account != null) unawaited(ref.read(localCacheProvider).clear(account));
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      notice: 'Your session has ended. Please sign in again.',
    );
  }
}
