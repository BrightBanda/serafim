import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Keeps what a moment showed on this phone, and plays a video while it is
/// still arriving.
///
/// * A **photo** is saved the first time it is fetched; next time it comes
///   from disk.
/// * A **video** is played from a tiny server on this phone (loopback only)
///   that downloads the file once from the signed link, hands the player each
///   part as soon as it has arrived, and keeps the whole file when the
///   download completes. Next time the saved file plays at once, with no
///   download. A player that jumps ahead (an MP4 that keeps its index at the
///   end) is answered straight from the server for that part, without waiting.
///
/// Leaving a video before it has finished downloading stops the download and
/// keeps nothing of it, so a quick skip doesn't spend someone's data.
///
/// Moments last 24 hours, so saved files go after [maxAge], and the oldest go
/// first when the cache passes [maxBytes].
class MomentMediaCache {
  MomentMediaCache({
    required this.directory,
    this.maxBytes = 300 * 1024 * 1024,
    this.maxAge = const Duration(hours: 26),
    this.useProxy = true,
    this.chunk = 64 * 1024,
    this.jumpAhead = 512 * 1024,
  });

  /// Where things are kept (made on first use).
  final Future<Directory> Function() directory;
  final int maxBytes;
  final Duration maxAge;

  /// Whether to play through the local server. Off, a video simply plays from
  /// its link (and is not kept).
  final bool useProxy;

  /// How much is handed to the player at a time.
  final int chunk;

  /// A request this far past what has arrived is answered from the source
  /// directly instead of waiting for the download to get there.
  final int jumpAhead;

  Future<Directory?>? _dir;
  Future<HttpServer>? _serverFuture;
  HttpServer? _server;
  final String _token = _randomToken();
  final Map<String, _Download> _downloads = {};

  static String _randomToken() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Directory?> _open() => _dir ??= () async {
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      // Before anything is written, so tidying can't meet a file being made.
      await prune();
      return dir;
    } catch (_) {
      // No place to keep things: everything still works, nothing is kept.
      return null;
    }
  }();

  // ------------------------------------------------------------- photos ---

  /// A photo moment's picture: from disk if it was seen before, otherwise from
  /// [fetch], and kept.
  Future<Uint8List> photo(String id, Future<Uint8List> Function() fetch) async {
    final dir = await _open();
    final file = dir == null ? null : File('${dir.path}/$id.jpg');
    if (file != null && await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          await file.setLastModified(DateTime.now());
          return bytes;
        }
      } catch (_) {}
    }
    final bytes = await fetch();
    if (file != null && bytes.isNotEmpty) {
      try {
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
      } catch (_) {}
    }
    return bytes;
  }

  // ------------------------------------------------------------- videos ---

  /// Where to play [id]'s video from: the saved file, or the local server that
  /// is downloading it, or (with no proxy) the link itself. [signedUrl] asks
  /// the server for a fresh link and is only called when one is needed.
  Future<Uri> video(String id, Future<String> Function() signedUrl) async {
    final dir = await _open();
    if (dir != null) {
      final done = File('${dir.path}/$id.mp4');
      if (await done.exists()) {
        await done.setLastModified(DateTime.now());
        return done.uri;
      }
    }
    if (!useProxy || dir == null) return Uri.parse(await signedUrl());

    // A download that failed is started again rather than served half-empty.
    if (_downloads[id]?.failed ?? false) _downloads.remove(id);
    final download = _downloads[id] ??= _Download(
      id: id,
      part: File('${dir.path}/$id.mp4.part'),
      done: File('${dir.path}/$id.mp4'),
      chunk: chunk,
      jumpAhead: jumpAhead,
    );
    try {
      await download.start(signedUrl);
    } catch (_) {
      _downloads.remove(id);
      rethrow;
    }
    final server = await _listen();
    return Uri.parse('http://127.0.0.1:${server.port}/$_token/$id.mp4');
  }

  /// Quietly gets [id]'s photo onto this phone ahead of being viewed, so it
  /// opens at once. Failing is fine: it is simply fetched when opened.
  Future<void> prefetchPhoto(String id, Future<Uint8List> Function() fetch) =>
      photo(id, fetch).then<void>((_) {}, onError: (_) {});

  /// The same for a video: it downloads in the background and is kept. Without
  /// the on-phone server nothing can be kept, so nothing is fetched.
  Future<void> prefetchVideo(
    String id,
    Future<String> Function() signedUrl,
  ) async {
    if (!useProxy) return;
    try {
      await video(id, signedUrl);
    } catch (_) {}
  }

  /// The viewer has moved on from [id]'s video. If it hasn't finished
  /// downloading, stop (and keep nothing of it).
  void release(String id) {
    final download = _downloads[id];
    if (download == null) return;
    download.releaseRequested = true;
    if (download.cancelIfIdle()) _downloads.remove(id);
  }

  Future<HttpServer> _listen() => _serverFuture ??= () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
    return server;
  }();

  Future<void> _handle(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    final id = parts.length == 2 && parts[0] == _token
        ? parts[1].replaceFirst(RegExp(r'\.mp4$'), '')
        : null;
    final download = id == null ? null : _downloads[id];
    if (download == null ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await download.serve(request);
    if (download.releaseRequested && download.cancelIfIdle()) {
      _downloads.remove(id);
    }
  }

  // -------------------------------------------------------------- upkeep ---

  /// Removes what is too old, what is left of interrupted downloads, and the
  /// oldest files beyond the size limit.
  Future<void> prune() async {
    try {
      final dir = await directory();
      if (!await dir.exists()) return;
      final now = DateTime.now();
      final keep = <File, FileStat>{};
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final stat = await entity.stat();
        final inUse = _downloads.values.any(
          (d) => d.part.path == entity.path && !d.finished,
        );
        if (inUse) continue;
        if (name.endsWith('.part') ||
            name.endsWith('.tmp') ||
            now.difference(stat.modified) > maxAge) {
          await entity.delete();
        } else {
          keep[entity] = stat;
        }
      }
      var total = keep.values.fold<int>(0, (sum, s) => sum + s.size);
      final oldestFirst = keep.entries.toList()
        ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
      for (final entry in oldestFirst) {
        if (total <= maxBytes) break;
        total -= entry.value.size;
        await entry.key.delete();
      }
    } catch (_) {}
  }

  /// Stops everything (the app is closing, or the account changed).
  Future<void> close() async {
    for (final d in _downloads.values) {
      d.cancel();
    }
    _downloads.clear();
    await _server?.close(force: true);
    _server = null;
    _serverFuture = null;
  }
}

/// One video being downloaded once, for as many requests as the player makes.
class _Download {
  _Download({
    required this.id,
    required this.part,
    required this.done,
    required this.chunk,
    required this.jumpAhead,
  });

  final String id;
  final File part;
  final File done;
  final int chunk;
  final int jumpAhead;

  String? _url;
  int total = 0;
  int downloaded = 0;
  bool complete = false;
  bool failed = false;
  bool releaseRequested = false;
  bool _cancelled = false;
  int _serving = 0;
  HttpClient? _client;
  Future<void>? _starting;
  final _progress = StreamController<void>.broadcast();

  /// Nothing more will be downloaded.
  bool get finished => complete || failed || _cancelled;

  Future<void> start(Future<String> Function() signedUrl) =>
      _starting ??= _begin(signedUrl);

  Future<void> _begin(Future<String> Function() signedUrl) async {
    _url = await signedUrl();
    final client = _client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_url!));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok || response.contentLength <= 0) {
        await response.drain<void>();
        throw HttpException('The video is not available.', uri: request.uri);
      }
      total = response.contentLength;
      final raf = await part.open(mode: FileMode.write);
      unawaited(_pump(response, raf));
    } catch (_) {
      failed = true;
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> _pump(HttpClientResponse response, RandomAccessFile raf) async {
    try {
      await for (final data in response) {
        if (_cancelled) break;
        await raf.writeFrom(data);
        downloaded += data.length;
        _progress.add(null);
      }
      await raf.close();
      if (_cancelled || downloaded != total) throw StateError('incomplete');
      await part.rename(done.path);
      complete = true;
    } catch (_) {
      failed = true;
      try {
        await raf.close();
      } catch (_) {}
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
    } finally {
      _client?.close(force: true);
      _progress.add(null);
    }
  }

  Future<void> _waitFor(int bytes) async {
    while (downloaded < bytes && !complete && !failed) {
      await _progress.stream.first;
    }
  }

  /// Stops if the viewer has left, the download isn't done and the player
  /// isn't still reading. Returns whether it stopped.
  bool cancelIfIdle() {
    if (complete || _serving > 0) return false;
    cancel();
    return true;
  }

  void cancel() {
    if (complete) return;
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> serve(HttpRequest request) async {
    final response = request.response;
    final range = _range(request.headers.value(HttpHeaders.rangeHeader));
    final start = range?.$1 ?? 0;
    final end = range?.$2 ?? total - 1;
    if (start < 0 || start >= total || end < start) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await response.close();
      return;
    }
    response.statusCode = range == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, 'video/mp4')
      ..contentLength = end - start + 1;
    if (range != null) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    _serving++;
    RandomAccessFile? raf;
    try {
      if (!complete && start > downloaded + jumpAhead) {
        await _passThrough(response, start, end);
        return;
      }
      var position = start;
      while (position <= end) {
        final want = min(position + chunk, end + 1);
        await _waitFor(want);
        final available = complete ? total : downloaded;
        if (available <= position) break; // the download failed
        raf ??= await _openForReading();
        final upTo = min(want, available);
        await raf.setPosition(position);
        final bytes = await raf.read(upTo - position);
        if (bytes.isEmpty) break;
        response.add(bytes);
        await response.flush();
        position += bytes.length;
      }
      await response.close();
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    } finally {
      await raf?.close();
      _serving--;
    }
  }

  /// The file being written, or the finished one: the download can complete
  /// (and rename its file) at any moment.
  Future<RandomAccessFile> _openForReading() async {
    try {
      return await (complete ? done : part).open();
    } on PathNotFoundException {
      return done.open();
    }
  }

  /// [start]..[end] straight from the source, for a player that jumped ahead.
  Future<void> _passThrough(HttpResponse response, int start, int end) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_url!));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final upstream = await request.close();
      await response.addStream(upstream);
      await response.close();
    } finally {
      client.close(force: true);
    }
  }

  /// `bytes=a-b`, `bytes=a-` or `bytes=-n`; null for none, or one we don't
  /// understand (then the whole file is sent).
  (int, int)? _range(String? header) {
    if (header == null) return null;
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null) return null;
    final a = m.group(1)!;
    final b = m.group(2)!;
    if (a.isEmpty && b.isEmpty) return null;
    if (a.isEmpty) {
      final n = int.parse(b);
      return (max(0, total - n), total - 1);
    }
    final first = int.parse(a);
    final last = b.isEmpty ? total - 1 : min(int.parse(b), total - 1);
    return (first, last);
  }
}
