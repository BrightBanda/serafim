import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A socket the test controls: what the app sends is recorded, and the test
/// decides what the "server" says.
class FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final _in = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool closedByApp = false;

  late final _sink = _FakeSink(this);

  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready => Future.value();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;

  void serverSays(Map<String, dynamic> frame) => _in.add(jsonEncode(frame));
  void serverDrops() => _in.close();
  List<String> get types => [for (final f in sent) f['type'] as String];
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._c);
  final FakeChannel _c;

  @override
  void add(dynamic data) =>
      _c.sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  @override
  Future close([int? closeCode, String? closeReason]) async =>
      _c.closedByApp = true;
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future get done => Future.value();
}

void main() {
  late List<FakeChannel> opened;
  late WebSocketService service;
  var now = DateTime(2026, 1, 1, 12);

  Future<void> settle(WidgetTester t, [Duration d = Duration.zero]) async {
    await t.pump(d);
    await t.pump();
  }

  WebSocketService make() {
    opened = [];
    now = DateTime(2026, 1, 1, 12);
    return WebSocketService(
      connector: (_) {
        final c = FakeChannel();
        opened.add(c);
        return c;
      },
      clock: () => now,
    );
  }

  Future<String?> token() async => 'tok';

  testWidgets('connects and authenticates', (t) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);
    expect(opened, hasLength(1));
    expect(opened.single.sent.first['type'], 'auth');
    service.disconnect();
  });

  testWidgets('after a drop it retries fast, then slows down', (t) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);

    opened.last.serverDrops();
    await settle(t);
    expect(opened, hasLength(1));

    await settle(t, const Duration(milliseconds: 600)); // first wait: 0.5 s
    expect(opened, hasLength(2), reason: 'not 5 seconds');

    opened.last.serverDrops();
    await settle(t, const Duration(milliseconds: 600));
    expect(opened, hasLength(2), reason: 'second wait is 1 s');
    await settle(t, const Duration(milliseconds: 500));
    expect(opened, hasLength(3));
    service.disconnect();
  });

  testWidgets('a link that works resets the waiting', (t) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);
    for (var i = 0; i < 3; i++) {
      opened.last.serverDrops();
      await settle(t, const Duration(seconds: 20));
    }
    final before = opened.length;
    opened.last.serverSays({'type': 'status', 'status': 'connected'});
    await settle(t);
    opened.last.serverDrops();
    await settle(t, const Duration(milliseconds: 600));
    expect(opened.length, before + 1, reason: 'back to the 0.5 s wait');
    service.disconnect();
  });

  testWidgets('returning after a long absence replaces the link at once', (
    t,
  ) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);
    final first = opened.single;

    service.onAppPaused();
    now = now.add(const Duration(minutes: 3));
    service.onAppResumed();
    await settle(t);

    expect(opened, hasLength(2));
    expect(first.closedByApp, isTrue);
    service.disconnect();
  });

  testWidgets('a short absence only checks the link, and keeps it if alive', (
    t,
  ) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);
    final ch = opened.single;
    ch.serverSays({'type': 'pong'}); // the server is known to answer pings
    await settle(t);

    service.onAppPaused();
    now = now.add(const Duration(seconds: 5));
    service.onAppResumed();
    await settle(t);
    expect(ch.types, contains('ping'));

    ch.serverSays({'type': 'pong'});
    await settle(t, const Duration(seconds: 11));
    expect(opened, hasLength(1), reason: 'it answered, so keep it');
    service.disconnect();
  });

  testWidgets('a silent link is replaced once the server is known to answer', (
    t,
  ) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);
    opened.single.serverSays({'type': 'pong'});
    await settle(t);

    await settle(t, const Duration(seconds: 25)); // heartbeat ping goes out
    expect(opened.single.types.where((x) => x == 'ping'), isNotEmpty);
    await settle(t, const Duration(seconds: 11)); // no answer
    expect(opened.length, greaterThanOrEqualTo(2));
    service.disconnect();
  });

  testWidgets('an older server that never answers is never held to it', (
    t,
  ) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);

    await settle(t, const Duration(seconds: 25));
    await settle(t, const Duration(seconds: 30));
    expect(opened, hasLength(1), reason: 'no pong ever: not judged');
    service.disconnect();
  });

  testWidgets('pong frames are not passed on to the app', (t) async {
    service = make();
    service.connect('http://x', 'me', token);
    await settle(t);
    final heard = <String>[];
    service.events.listen((m) => heard.add(m['type'] as String));

    opened.single.serverSays({'type': 'pong'});
    opened.single.serverSays({'type': 'message'});
    await settle(t);
    expect(heard, ['message']);
    service.disconnect();
  });
}
