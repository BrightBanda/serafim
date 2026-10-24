import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/services/profile_service.dart';

/// The real service against a pretend server: the part a fake service skips.
class _Server implements HttpClientAdapter {
  _Server(this.reply, {this.status = 200});

  final Object? reply;
  final int status;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ProfileService _service(_Server server) => ProfileService(
  Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = server,
);

void main() {
  test('lighting the halo returns the time the server gave', () async {
    final server = _Server({
      'halo_until': '2030-01-01T12:30:00+00:00',
      'halo_audience': 'wings',
    });
    final until = await _service(server).lightHalo(60, wingsOnly: true);
    expect(until, DateTime.utc(2030, 1, 1, 12, 30));
    final sent = server.seen.single;
    expect(sent.method, 'PUT');
    expect(sent.path, '/profile/me/halo');
    expect(sent.data, {'minutes': 60, 'audience': 'wings'});
  });

  test('all friends is the default audience', () async {
    final server = _Server({'halo_until': '2030-01-01T12:30:00Z'});
    await _service(server).lightHalo(30);
    expect((server.seen.single.data as Map)['audience'], 'friends');
  });

  test('putting it out works and sends a DELETE', () async {
    final server = _Server({'halo_until': null, 'halo_audience': 'friends'});
    await _service(server).dimHalo();
    expect(server.seen.single.method, 'DELETE');
  });

  test('a reply with no time is an error, not a crash', () async {
    final server = _Server({'halo_until': null});
    expect(_service(server).lightHalo(60), throwsA(isA<ApiException>()));
  });

  test('a server error is an ApiException with its message', () async {
    final server = _Server({'detail': 'Profile not found.'}, status: 404);
    expect(_service(server).lightHalo(60), throwsA(isA<ApiException>()));
  });
}
