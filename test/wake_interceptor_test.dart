import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/wake_interceptor.dart';

/// Answers from a closure, and records the URLs it was asked for.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions o) respond;
  final List<String> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o.uri.toString());
    return respond(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, [Map<String, List<String>> headers = const {}]) =>
    ResponseBody.fromString(
      '{"ok":true}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
    );

ResponseBody asleep() => json(429, {
  'x-render-routing': ['hibernate-rate-limited'],
});

const direct = 'https://direct.example.com';

({
  Dio api,
  FakeAdapter apiAdapter,
  FakeAdapter wakeAdapter,
  bool Function() awake,
})
build({
  bool wakeFails = false,
  bool alwaysAsleep = false,
  String directUrl = direct,
}) {
  var awake = false;
  final wakeAdapter = FakeAdapter((o) {
    if (wakeFails) {
      throw DioException(
        requestOptions: o,
        type: DioExceptionType.connectionError,
      );
    }
    awake = true;
    return json(200);
  });
  final apiAdapter = FakeAdapter(
    (o) => awake && !alwaysAsleep ? json(200) : asleep(),
  );
  final api = Dio(BaseOptions(baseUrl: 'https://worker.example.com'))
    ..httpClientAdapter = apiAdapter;
  WakeInterceptor(
    directUrl: directUrl,
    wakeClient: Dio()..httpClientAdapter = wakeAdapter,
  ).attachTo(api);
  return (
    api: api,
    apiAdapter: apiAdapter,
    wakeAdapter: wakeAdapter,
    awake: () => awake,
  );
}

void main() {
  test(
    'a sleeping-server refusal wakes it directly, then replays once',
    () async {
      final t = build();
      final response = await t.api.get<dynamic>('/chats');
      expect(response.statusCode, 200);
      expect(t.wakeAdapter.seen, ['$direct/health']);
      expect(t.apiAdapter.seen, [
        'https://worker.example.com/chats',
        'https://worker.example.com/chats',
      ]);
    },
  );

  test('requests that find it asleep together share one wake-up', () async {
    final t = build();
    final results = await Future.wait([
      t.api.get<dynamic>('/a'),
      t.api.get<dynamic>('/b'),
      t.api.get<dynamic>('/c'),
    ]);
    expect(results.every((r) => r.statusCode == 200), isTrue);
    expect(t.wakeAdapter.seen, hasLength(1));
  });

  test(
    'a server that keeps refusing is replayed once, not in a loop',
    () async {
      final t = build(alwaysAsleep: true);
      await expectLater(
        t.api.get<dynamic>('/chats'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            429,
          ),
        ),
      );
      expect(t.wakeAdapter.seen, hasLength(1));
      expect(t.apiAdapter.seen, hasLength(2));
    },
  );

  test(
    'a direct address that cannot be reached keeps the original error',
    () async {
      final t = build(wakeFails: true);
      await expectLater(
        t.api.get<dynamic>('/chats'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            429,
          ),
        ),
      );
      expect(t.apiAdapter.seen, hasLength(1));
    },
  );

  test('a real rate limit is left alone', () async {
    final wakeAdapter = FakeAdapter((_) => json(200));
    final api = Dio(BaseOptions(baseUrl: 'https://worker.example.com'))
      ..httpClientAdapter = FakeAdapter((_) => json(429));
    WakeInterceptor(
      directUrl: direct,
      wakeClient: Dio()..httpClientAdapter = wakeAdapter,
    ).attachTo(api);
    await expectLater(api.get<dynamic>('/x'), throwsA(isA<DioException>()));
    expect(wakeAdapter.seen, isEmpty);
  });

  test('an empty direct address turns it off', () async {
    final t = build(directUrl: '');
    await expectLater(
      t.api.get<dynamic>('/chats'),
      throwsA(isA<DioException>()),
    );
    expect(t.wakeAdapter.seen, isEmpty);
  });
}
