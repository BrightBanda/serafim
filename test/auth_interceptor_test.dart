import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/core/network/auth_interceptor.dart';
import 'package:serafim/src/data/models/auth_session.dart';

import 'support/fakes.dart';

/// A server that answers each request according to the bearer token it sees.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.respond);

  final ResponseBody Function(String? bearer) respond;
  final List<String?> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    final bearer = o.headers['Authorization'] as String?;
    seen.add(bearer);
    return respond(bearer);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody ok() => ResponseBody.fromString(
  '{"ok":true}',
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody denied() => ResponseBody.fromString(
  jsonEncode({'detail': 'Invalid or missing access token.'}),
  401,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

AuthSession refreshed(String access) => AuthSession(
  accessToken: access,
  refreshToken: 'refresh-2',
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  userId: 'u1',
);

({Dio dio, FakeSessionStore store, FakeAuthService auth, FakeServer server})
build({
  required AuthSession? session,
  required ResponseBody Function(String? bearer) server,
  required Future<AuthSession> Function(String) onRefresh,
}) {
  final store = FakeSessionStore(session);
  final auth = FakeAuthService(onRefresh: onRefresh);
  final fake = FakeServer(server);
  final dio = Dio(BaseOptions(baseUrl: 'http://api'))..httpClientAdapter = fake;
  AuthInterceptor(store: store, authService: auth).attachTo(dio);
  return (dio: dio, store: store, auth: auth, server: fake);
}

void main() {
  group('a token that has expired', () {
    test(
      'is refreshed first, and the request goes out with the new one',
      () async {
        final t = build(
          session: fakeSession(expired: true),
          server: (b) => b == 'Bearer fresh' ? ok() : denied(),
          onRefresh: (_) async => refreshed('fresh'),
        );
        final r = await t.dio.get<dynamic>('/x');
        expect(r.statusCode, 200);
        expect(t.auth.refreshCalls, 1);
        expect(t.store.current!.accessToken, 'fresh');
      },
    );

    test(
      'many requests at once cause one refresh, not a race that burns the token',
      () async {
        final gate = Completer<AuthSession>();
        final t = build(
          session: fakeSession(expired: true),
          server: (_) => ok(),
          onRefresh: (_) => gate.future,
        );
        final calls = [for (var i = 0; i < 5; i++) t.dio.get<dynamic>('/x')];
        await pumpEventQueue();
        gate.complete(refreshed('fresh'));
        await Future.wait(calls);
        expect(t.auth.refreshCalls, 1);
      },
    );

    test(
      'OFFLINE: the request fails like any connection error — and you stay signed in',
      () async {
        final t = build(
          session: fakeSession(expired: true),
          server: (_) => ok(),
          onRefresh: (_) async =>
              throw const ApiException("Can't reach the server."),
        );
        await expectLater(
          t.dio.get<dynamic>('/x'),
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.connectionError,
            ),
          ),
        );
        expect(
          t.store.current,
          isNotNull,
          reason: 'being offline must not sign you out',
        );
        expect(t.store.clearCount, 0);
        expect(
          t.server.seen,
          isEmpty,
          reason: 'no request goes out with a stale token',
        );
      },
    );

    test(
      'the auth server having a bad day (500) also keeps you signed in',
      () async {
        final t = build(
          session: fakeSession(expired: true),
          server: (_) => ok(),
          onRefresh: (_) async =>
              throw const ApiException('down', statusCode: 503),
        );
        await expectLater(
          t.dio.get<dynamic>('/x'),
          throwsA(isA<DioException>()),
        );
        expect(t.store.clearCount, 0);
      },
    );

    test('rate limiting (429) is not a revoked login', () async {
      final t = build(
        session: fakeSession(expired: true),
        server: (_) => ok(),
        onRefresh: (_) async =>
            throw const ApiException('slow down', statusCode: 429),
      );
      await expectLater(t.dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(t.store.clearCount, 0);
    });

    test(
      'REVOKED or deleted user: the auth server refuses, so the login is cleared',
      () async {
        final t = build(
          session: fakeSession(expired: true),
          server: (_) => denied(),
          onRefresh: (_) async => throw const ApiException(
            'Invalid Refresh Token',
            statusCode: 400,
          ),
        );
        await expectLater(
          t.dio.get<dynamic>('/x'),
          throwsA(isA<DioException>()),
        );
        expect(t.store.current, isNull);
        expect(t.store.clearCount, 1);
      },
    );

    test(
      'a crash inside the refresh is treated as "can\'t tell", not "signed out"',
      () async {
        final t = build(
          session: fakeSession(expired: true),
          server: (_) => ok(),
          onRefresh: (_) async => throw StateError('unexpected'),
        );
        await expectLater(
          t.dio.get<dynamic>('/x'),
          throwsA(isA<DioException>()),
        );
        expect(t.store.clearCount, 0);
      },
    );
  });

  group('a request the server rejects with 401', () {
    test('is replayed once with a refreshed token', () async {
      final t = build(
        session: fakeSession(),
        server: (b) => b == 'Bearer fresh' ? ok() : denied(),
        onRefresh: (_) async => refreshed('fresh'),
      );
      final r = await t.dio.get<dynamic>('/x');
      expect(r.statusCode, 200);
      expect(t.server.seen, ['Bearer access-1', 'Bearer fresh']);
    });

    test(
      'DELETED ACCOUNT: a brand-new token is refused too, so the session ends',
      () async {
        // The login refreshes fine (the auth record may still exist) but our
        // server says no to every token. This used to leave the app stuck.
        final t = build(
          session: fakeSession(),
          server: (_) => denied(),
          onRefresh: (_) async => refreshed('fresh'),
        );
        await expectLater(
          t.dio.get<dynamic>('/x'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(t.store.current, isNull);
        expect(t.store.clearCount, 1);
      },
    );

    test('it is replayed only once: no retry loop', () async {
      final t = build(
        session: fakeSession(),
        server: (_) => denied(),
        onRefresh: (_) async => refreshed('fresh'),
      );
      await expectLater(t.dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(t.server.seen.length, 2);
      expect(t.auth.refreshCalls, 1);
    });

    test(
      'offline during the refresh: the 401 comes back but the login is untouched',
      () async {
        final t = build(
          session: fakeSession(),
          server: (_) => denied(),
          onRefresh: (_) async => throw const ApiException('offline'),
        );
        await expectLater(
          t.dio.get<dynamic>('/x'),
          throwsA(isA<DioException>()),
        );
        expect(t.store.clearCount, 0);
      },
    );

    test('a 500 is just a 500: nothing is refreshed or cleared', () async {
      final t = build(
        session: fakeSession(),
        server: (_) => ResponseBody.fromString('oops', 500),
        onRefresh: (_) async => refreshed('fresh'),
      );
      await expectLater(t.dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(t.auth.refreshCalls, 0);
      expect(t.store.clearCount, 0);
    });
  });

  test(
    'with no login at all, requests simply go out without a token',
    () async {
      final t = build(
        session: null,
        server: (b) => b == null ? ok() : denied(),
        onRefresh: (_) async => refreshed('x'),
      );
      expect((await t.dio.get<dynamic>('/public')).statusCode, 200);
      expect(t.auth.refreshCalls, 0);
    },
  );
}
