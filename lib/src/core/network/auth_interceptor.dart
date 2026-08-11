import 'package:dio/dio.dart';
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
  AuthInterceptor({required SessionStore store, required AuthService authService})
    : _store = store,
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
      session = await _refresh(session.refreshToken);
    }

    if (session != null) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final session = _store.current;

    final canRetry = err.response?.statusCode == 401 &&
        session != null &&
        options.extra[_retriedKey] != true;

    if (!canRetry) {
      handler.next(err);
      return;
    }

    final refreshed = await _refresh(session.refreshToken);
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
    } catch (_) {
      // Revoked, expired, or rotated out from under us — the only honest
      // answer is to sign out. Clearing emits on SessionStore.changes, which
      // is what moves AuthViewModel to unauthenticated.
      await _store.clear();
      return null;
    }
  }
}
