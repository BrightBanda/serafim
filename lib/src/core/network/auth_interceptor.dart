import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/auth_session.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/data/services/session_store.dart';

/// Keeps the backend dio client authenticated without any caller thinking
/// about tokens.
///
/// Two jobs:
///   1. Attach `Authorization: Bearer <token>` to every outbound request,
///      refreshing first if the token is about to expire.
///   2. Recover from a 401 by refreshing once and replaying the request.
///
/// Refreshes are single-flighted: if ten requests fire at launch and all find
/// an expired token, exactly one hits GoTrue and the rest await that future.
/// Without this the rotating refresh token would race with itself and Supabase
/// would invalidate the whole chain.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required SessionStore store,
    required AuthService authService,
  }) : _store = store,
       _authService = authService;

  /// Marks a request that has already been replayed after a refresh, so a
  /// server that keeps answering 401 cannot put us in a retry loop.
  static const _retriedKey = 'serafim.auth.retried';

  final SessionStore _store;
  final AuthService _authService;

  late final Dio _client;
  Future<AuthSession?>? _inFlightRefresh;

  /// Installs this interceptor on [dio] and remembers it for replaying
  /// requests. Splitting this from the constructor avoids the chicken-and-egg
  /// of needing the client before it exists.
  void attachTo(Dio dio) {
    _client = dio;
    dio.interceptors.add(this);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    var session = _store.current;

    if (session != null && session.isExpired) {
      try {
        session = await _refresh(session.refreshToken);
      } on TransientAuthFailure catch (failure) {
        // Offline (or the auth server is down), not signed out: fail this one
        // request like any other connection problem and keep the login for
        // when the network is back.
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: failure,
          ),
        );
        return;
      }
    }

    if (session != null) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final session = _store.current;

    final canRetry =
        err.response?.statusCode == 401 &&
        session != null &&
        options.extra[_retriedKey] != true;

    if (!canRetry) {
      handler.next(err);
      return;
    }

    final AuthSession? refreshed;
    try {
      refreshed = await _refresh(session.refreshToken);
    } on TransientAuthFailure {
      handler.next(err); // Can't tell yet; leave the login alone.
      return;
    }
    if (refreshed == null) {
      // Refresh failed and the session has been cleared; surface the original
      // 401 so the view model can route back to sign-in.
      handler.next(err);
      return;
    }

    options.extra[_retriedKey] = true;
    options.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';

    try {
      handler.resolve(await _client.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      // A brand-new token was refused too. The login is not coming back (the
      // account was deleted or disabled), so end the session rather than
      // leaving the app stuck retrying.
      if (retryError.response?.statusCode == 401) await _store.clear();
      handler.next(retryError);
    }
  }

  /// Refreshes and persists the session, or clears it and returns null if the
  /// refresh token is no longer good.
  Future<AuthSession?> _refresh(String refreshToken) {
    return _inFlightRefresh ??= _performRefresh(refreshToken).whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<AuthSession?> _performRefresh(String refreshToken) async {
    try {
      final session = await _authService.refresh(refreshToken);
      await _store.save(session);
      return session;
    } on ApiException catch (error) {
      // The auth server answered and said no: revoked, expired, rotated out
      // from under us, or the user no longer exists. The only honest answer is
      // to sign out. Clearing emits on SessionStore.changes, which is what
      // moves AuthViewModel to unauthenticated.
      final refused =
          error.statusCode != null &&
          error.statusCode! < 500 &&
          error.statusCode != 429;
      if (refused) {
        await _store.clear();
        return null;
      }
      // No answer (offline, timeout) or the auth server is struggling: that
      // says nothing about the login, so keep it.
      throw const TransientAuthFailure();
    } catch (_) {
      throw const TransientAuthFailure();
    }
  }
}

/// Refreshing the token failed for a reason that does not mean the login is
/// invalid (no network, auth server down). The session is kept.
class TransientAuthFailure implements Exception {
  const TransientAuthFailure();
  @override
  String toString() => 'TransientAuthFailure';
}
