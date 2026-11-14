import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/services/moment_media_cache.dart';

/// Stands in for the signed link: serves [bytes] with Range support, [pieces]
/// at a time with [pause] between them, and counts what was asked of it.
class Source {
  Source(this.bytes, {this.pieces = 8, this.pause = Duration.zero});

  final Uint8List bytes;
  int pieces;
  Duration pause;
  bool refuse = false;
  final requests = <String?>[]; // the Range header of each request
  late final HttpServer server;
  final _release = Completer<void>();

  /// Holds the download back until the test lets go (after the first bytes).
  Completer<void>? gate;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      requests.add(range);
      final res = request.response;
      if (refuse) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      var start = 0;
      var end = bytes.length - 1;
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
        res.statusCode = HttpStatus.partialContent;
      }
      res.contentLength = end - start + 1;
      final slice = bytes.sublist(start, end + 1);
      final step = (slice.length / pieces).ceil();
      try {
        for (var i = 0; i < slice.length; i += step) {
          res.add(slice.sublist(i, (i + step).clamp(0, slice.length)));
          await res.flush();
          if (range == null && i == 0 && gate != null) await gate!.future;
          if (pause > Duration.zero) await Future<void>.delayed(pause);
        }
        await res.close();
      } catch (_) {}
    });
  }

  String get url => 'http://127.0.0.1:${server.port}/video.mp4';

  Future<void> stop() async {
    if (!_release.isCompleted) _release.complete();
    await server.close(force: true);
  }
}

Uint8List fakeVideo(int size) =>
    Uint8List.fromList(List.generate(size, (i) => (i * 7 + i ~/ 251) % 256));

/// Asks the on-phone server for [range] of [uri]; returns status and body.
Future<(int, List<int>, HttpHeaders)> fetch(Uri uri, {String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final body = <int>[];
    await for (final chunk in response) {
      body.addAll(chunk);
    }
    return (response.statusCode, body, response.headers);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory dir;
  late MomentMediaCache cache;
  late Source source;
  final video = fakeVideo(400 * 1024);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('moment_cache');
    cache = MomentMediaCache(
      directory: () async => dir,
      chunk: 16 * 1024,
      jumpAhead: 64 * 1024,
    );
    source = Source(video);
    await source.start();
  });

  tearDown(() async {
    await cache.close();
    await source.stop();
    dir.deleteSync(recursive: true);
  });

  File saved(String id) => File('${dir.path}/$id.mp4');
  File part(String id) => File('${dir.path}/$id.mp4.part');

  Future<Uri> open([String id = 'm1']) async =>
      cache.video(id, () async => source.url);

  group('ahead of time', () {
    test('a video is downloaded and kept before anyone opens it', () async {
      await cache.prefetchVideo('m1', () async => source.url);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(saved('m1').readAsBytesSync(), video);
      final before = source.requests.length;
      final uri = await open();
      expect(uri.scheme, 'file');
      expect(source.requests.length, before, reason: 'no second download');
    });

    test('one that failed is tried again when opened', () async {
      source.refuse = true;
      await cache.prefetchVideo('m1', () async => source.url);
      source.refuse = false;
      final uri = await open();
      final (status, body, _) = await fetch(uri);
      expect(status, 200);
      expect(body, video);
    });

    test('a photo is kept ahead of being viewed', () async {
      var fetched = 0;
      Future<Uint8List> get() async {
        fetched++;
        return Uint8List.fromList([1, 2, 3]);
      }

      await cache.prefetchPhoto('p', get);
      expect(await cache.photo('p', get), [1, 2, 3]);
      expect(fetched, 1);
    });
  });

  group('videos', () {
    test(
      'play from the first bytes, and are kept when the download ends',
      () async {
        source.gate = Completer<void>();
        final uri = await open();
        expect(uri.host, '127.0.0.1');

        // The first part comes back while the source is still holding the rest.
        final client = HttpClient();
        final request = await client.getUrl(uri);
        final response = await request.close();
        final chunks = StreamIterator(response);
        expect(await chunks.moveNext(), isTrue);
        final first = chunks.current;
        expect(first, isNotEmpty);
        expect(saved('m1').existsSync(), isFalse, reason: 'still arriving');

        source.gate!.complete();
        final rest = <int>[...first];
        while (await chunks.moveNext()) {
          rest.addAll(chunks.current);
        }
        client.close();
        expect(rest, video);

        // Kept: once the download is done the saved file is there.
        for (var i = 0; i < 50 && !saved('m1').existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(saved('m1').readAsBytesSync(), video);
        expect(part('m1').existsSync(), isFalse);
        expect(source.requests, [null], reason: 'downloaded once');
      },
    );

    test(
      'seen again, they play from the file with no download at all',
      () async {
        final uri = await open();
        await fetch(uri);
        for (var i = 0; i < 50 && !saved('m1').existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        source.requests.clear();

        final again = await open();
        expect(again.scheme, 'file');
        expect(File.fromUri(again).readAsBytesSync(), video);
        expect(source.requests, isEmpty);
      },
    );

    test('a player asking for a part gets exactly that part', () async {
      final uri = await open();
      final (status, body, headers) = await fetch(
        uri,
        range: 'bytes=1000-1999',
      );
      expect(status, HttpStatus.partialContent);
      expect(body, video.sublist(1000, 2000));
      expect(
        headers.value(HttpHeaders.contentRangeHeader),
        'bytes 1000-1999/${video.length}',
      );
      final (_, open0, _) = await fetch(uri, range: 'bytes=0-');
      expect(open0, video);
      final (_, tail, _) = await fetch(uri, range: 'bytes=-500');
      expect(tail, video.sublist(video.length - 500));
    });

    test('asking past the end is refused', () async {
      final uri = await open();
      final (status, _, _) = await fetch(
        uri,
        range: 'bytes=${video.length + 5}-',
      );
      expect(status, HttpStatus.requestedRangeNotSatisfiable);
    });

    test(
      'a player that jumps ahead (index at the end) is not made to wait',
      () async {
        source.gate = Completer<void>(); // the main download is held up
        final uri = await open();
        final from = video.length - 5000;
        final (status, body, _) = await fetch(uri, range: 'bytes=$from-');
        expect(status, HttpStatus.partialContent);
        expect(body, video.sublist(from));
        expect(
          source.requests.where((r) => r == 'bytes=$from-${video.length - 1}'),
          hasLength(1),
        );
        expect(saved('m1').existsSync(), isFalse);
        source.gate!.complete();
      },
    );

    test(
      'leaving before it has arrived stops the download and keeps nothing',
      () async {
        source
          ..gate = Completer<void>()
          ..pause = const Duration(milliseconds: 20);
        await open();
        cache.release('m1');
        source.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(saved('m1').existsSync(), isFalse);
        expect(part('m1').existsSync(), isFalse);

        // Coming back starts it afresh.
        source.pause = Duration.zero;
        source.requests.clear();
        final uri = await open();
        final (_, body, _) = await fetch(uri);
        expect(body, video);
        expect(source.requests, [null]);
      },
    );

    test('leaving after it has finished keeps it', () async {
      final uri = await open();
      await fetch(uri);
      for (var i = 0; i < 50 && !saved('m1').existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      cache.release('m1');
      expect(saved('m1').existsSync(), isTrue);
    });

    test('a source that refuses is an error and leaves nothing', () async {
      source.refuse = true;
      await expectLater(open(), throwsA(isA<HttpException>()));
      expect(dir.listSync(), isEmpty);
      // And it can be tried again.
      source.refuse = false;
      final uri = await open();
      expect((await fetch(uri)).$2, video);
    });

    test(
      'only this app can ask: the wrong key or an unknown video is 404',
      () async {
        final uri = await open();
        final wrongKey = uri.replace(pathSegments: ['not-the-key', 'm1.mp4']);
        expect((await fetch(wrongKey)).$1, HttpStatus.notFound);
        final unknown = uri.replace(
          pathSegments: [uri.pathSegments[0], 'zzz.mp4'],
        );
        expect((await fetch(unknown)).$1, HttpStatus.notFound);
      },
    );

    test('without the on-phone server it just plays from the link', () async {
      final plain = MomentMediaCache(
        directory: () async => dir,
        useProxy: false,
      );
      final uri = await plain.video('m1', () async => source.url);
      expect(uri.toString(), source.url);
      expect(source.requests, isEmpty);
      await plain.close();
    });

    test('with nowhere to keep things it still plays', () async {
      final nowhere = MomentMediaCache(
        directory: () async => throw const FileSystemException('no space'),
        useProxy: true,
      );
      final uri = await nowhere.video('m1', () async => source.url);
      expect(uri.toString(), source.url);
      await nowhere.close();
    });
  });

  group('photos', () {
    test('are fetched once and then come from the phone', () async {
      var fetched = 0;
      Future<Uint8List> get() async {
        fetched++;
        return Uint8List.fromList([1, 2, 3]);
      }

      expect(await cache.photo('p1', get), [1, 2, 3]);
      expect(await cache.photo('p1', get), [1, 2, 3]);
      expect(fetched, 1);
      expect(File('${dir.path}/p1.jpg').existsSync(), isTrue);
    });

    test('with nowhere to keep them they are still shown', () async {
      final nowhere = MomentMediaCache(
        directory: () async => throw const FileSystemException('no space'),
      );
      expect(await nowhere.photo('p1', () async => Uint8List.fromList([9])), [
        9,
      ]);
    });
  });

  group('upkeep', () {
    test(
      'old files, unfinished downloads and the oldest beyond the limit go',
      () async {
        File make(String name, int size, {Duration age = Duration.zero}) {
          final f = File('${dir.path}/$name')
            ..writeAsBytesSync(Uint8List(size));
          f.setLastModifiedSync(DateTime.now().subtract(age));
          return f;
        }

        final small = MomentMediaCache(
          directory: () async => dir,
          maxBytes: 250,
          maxAge: const Duration(hours: 26),
        );
        make('old.mp4', 100, age: const Duration(hours: 30));
        make('half.mp4.part', 100);
        make('left.jpg.tmp', 10);
        make('a.jpg', 100, age: const Duration(hours: 3));
        make('b.jpg', 100, age: const Duration(hours: 2));
        make('c.jpg', 100, age: const Duration(hours: 1));

        await small.prune();
        final left = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
        expect(left, {'b.jpg', 'c.jpg'}); // a.jpg was the oldest past the limit
        await small.close();
      },
    );
  });
}
