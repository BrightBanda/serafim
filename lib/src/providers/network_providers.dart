import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/auth_interceptor.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';

const _timeouts = (
  connect: Duration(seconds: 15),
  receive: Duration(seconds: 20),
  send: Duration(seconds: 20),
);

/// Dio client for Supabase GoTrue.
///
/// Deliberately *not* authenticated by [AuthInterceptor]: this is the client
/// the interceptor itself uses to refresh, so adding it here would recurse.
/// Requests carry the publishable key instead, which is all GoTrue needs.
final supabaseDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.supabaseAuthUrl,
      connectTimeout: _timeouts.connect,
      receiveTimeout: _timeouts.receive,
      sendTimeout: _timeouts.send,
      contentType: Headers.jsonContentType,
      headers: {
        'apikey': config.supabasePublishableKey,
        // GoTrue wants a bearer even for anonymous calls; the publishable key
        // doubles as one until a real session exists. Once a user signs in,
        // AuthService sends their access token explicitly where it matters.
        'Authorization': 'Bearer ${config.supabasePublishableKey}',
      },
    ),
  );

  ref.onDispose(dio.close);
  return dio;
});

/// Dio client for the Serafim FastAPI backend.
///
/// Every request through this client is authenticated, refreshed, and replayed
/// by [AuthInterceptor] — services built on it never touch a token.
final apiDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: _timeouts.connect,
      receiveTimeout: _timeouts.receive,
      sendTimeout: _timeouts.send,
      contentType: Headers.jsonContentType,
    ),
  );

  AuthInterceptor(
    store: ref.watch(sessionStoreProvider),
    authService: ref.watch(authServiceProvider),
  ).attachTo(dio);

  ref.onDispose(dio.close);
  return dio;
});
