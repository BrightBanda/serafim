import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/auth_session.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/data/services/session_store.dart';
import 'package:serafim/src/data/services/user_service.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';

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
  const AuthState({required this.status, this.user, this.isBusy = false});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);

  final AuthStatus status;

  /// The application user row, populated from `POST /auth/sync`.
  final AppUser? user;

  /// True while a sign-in, sign-up, or sign-out is in flight.
  final bool isBusy;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({AuthStatus? status, AppUser? user, bool? isBusy}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isBusy: isBusy ?? this.isBusy,
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
    unawaited(_restore());

    return const AuthState.unknown();
  }

  /// Reads any persisted session and, if it is still good, syncs the backend
  /// user row. Any failure resolves to signed-out.
  Future<void> _restore() async {
    final session = await _store.restore();
    if (!ref.mounted) return;

    if (session == null) {
      state = const AuthState.unauthenticated();
      return;
    }

    try {
      final user = await _users.sync();
      if (!ref.mounted) return;
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException catch (error) {
      if (!ref.mounted) return;

      // A null status means the request never reached the backend at all —
      // it is down, or API_BASE_URL is wrong. The session is still good, so
      // keep it and let the user retry once the server is up.
      state = error.statusCode == null
          ? const AuthState(status: AuthStatus.backendUnavailable)
          // Expired beyond refresh or revoked. The interceptor has already
          // cleared the store if the token was the problem.
          : const AuthState.unauthenticated();
    }
  }

  /// Re-attempts the startup sync. Wired to the retry button shown for
  /// [AuthStatus.backendUnavailable].
  Future<void> retryBackendSync() async {
    state = state.copyWith(isBusy: true);
    await _restore();
    if (ref.mounted && state.isBusy) state = state.copyWith(isBusy: false);
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

  Future<void> signOut() async {
    final session = _store.current;
    state = state.copyWith(isBusy: true);

    if (session != null) {
      await _auth.signOut(session.accessToken);
    }
    // Clearing emits on SessionStore.changes, which drives the state below,
    // but set it here too so the transition is immediate rather than waiting
    // on a microtask.
    await _store.clear();
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
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException catch (error) {
      // The Supabase account now exists but our own row does not. Say which
      // server failed — "could not reach the server" is unhelpful when the
      // flow just talked to two of them. The session stays saved, so a retry
      // or a relaunch picks up where this left off rather than attempting a
      // duplicate registration.
      if (error.statusCode == null) {
        state = const AuthState(status: AuthStatus.backendUnavailable);
        throw ApiException(
          'Your account was created, but the Serafim backend at '
          '${ref.read(appConfigProvider).apiBaseUrl} did not respond. '
          'Start the server and try again — you will not need to sign up twice.',
        );
      }
      rethrow;
    }
  }

  void _onSessionChanged(AuthSession? session) {
    if (session == null && state.isAuthenticated) {
      state = const AuthState.unauthenticated();
    }
  }
}
