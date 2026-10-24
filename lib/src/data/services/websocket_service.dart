// lib/src/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:serafim/src/core/debug_log.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Supplies a currently valid access token, refreshing first if needed.
/// Called on every (re)connect because tokens expire between reconnects.
typedef TokenProvider = Future<String?> Function();

/// Opens the socket. Replaceable so the timing logic can be tested.
typedef ChannelConnector = WebSocketChannel Function(Uri uri);

/// The live link to the server: messages, receipts, typing.
///
/// A phone's operating system quietly kills network connections of apps in
/// the background, and nothing tells the app. So this does three things to
/// make a message show up as soon as the app is opened:
///  * **reconnects at once when the app comes back**, if it was away long
///    enough for the link to have died;
///  * **retries quickly** after a drop (0.5 s, 1 s, 2 s … up to 15 s) instead
///    of a flat 5 s;
///  * **checks the link is alive** while the app is open: a small `ping` every
///    [heartbeatEvery]; if the server answers `pong` once, it is expected to
///    keep answering, and silence for [heartbeatTimeout] means the link is
///    dead and is replaced. (A server that never answers is never held to it.)
class WebSocketService {
  WebSocketService({
    ChannelConnector? connector,
    this.heartbeatEvery = const Duration(seconds: 25),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.awayLongEnough = const Duration(seconds: 15),
    this.backoff = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
    DateTime Function()? clock,
  }) : _connector = connector ?? WebSocketChannel.connect,
       _clock = clock ?? DateTime.now;

  final ChannelConnector _connector;
  final DateTime Function() _clock;
  final Duration heartbeatEvery;
  final Duration heartbeatTimeout;

  /// Coming back after at least this long, the old link is assumed dead.
  final Duration awayLongEnough;

  /// Waits before successive reconnect attempts; the last one repeats.
  final List<Duration> backoff;

  /// Connection notes in debug builds only (`[ws] …`; see `trace`).
  void _log(String message) => trace('ws', message);

  WebSocketChannel? _channel;

  /// Every frame from the server, across reconnects and accounts. Created
  /// with the service and closed only by [disconnect], so a subscriber keeps
  /// hearing events however often the link is replaced.
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  Timer? _reconnectTimer;
  Timer? _heartbeat;
  Timer? _deadline;

  String? _lastBaseUrl;
  String? _lastUserId;
  TokenProvider? _tokenProvider;
  bool _isExplicitDisconnect = false;

  int _attempt = 0;
  bool _pongSeen = false;
  bool _heardSincePing = true;
  DateTime? _pausedAt;

  /// Incoming frames from the server (decoded JSON), plus a
  /// `{'type': 'status', 'status': 'disconnected'}` when the link drops.
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Whether a socket is currently open (it may still turn out to be dead).
  bool get hasChannel => _channel != null;

  /// Connects to the FastAPI WebSocket endpoint and authenticates.
  ///
  /// The server ignores the user id in the URL until the first frame proves it
  /// with an access token.
  void connect(String baseUrl, String userId, TokenProvider tokenProvider) {
    _lastBaseUrl = baseUrl;
    _lastUserId = userId;
    _tokenProvider = tokenProvider;
    _isExplicitDisconnect = false;

    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatEvery, (_) => _ping());
    _attempt = 0;
    _open();
  }

  Future<void> _open() async {
    final baseUrl = _lastBaseUrl;
    final userId = _lastUserId;
    final tokenProvider = _tokenProvider;
    if (baseUrl == null || userId == null || tokenProvider == null) return;

    // Drop any previous channel without letting its onDone schedule a retry.
    final previous = _channel;
    _channel = null;
    previous?.sink.close();
    _deadline?.cancel();
    _log('opening (attempt $_attempt)');

    String? token;
    try {
      token = await tokenProvider();
    } catch (_) {
      token = null;
    }
    if (_isExplicitDisconnect) return;
    if (token == null || token.isEmpty) {
      _log('no token yet, will retry');
      _handleReconnect();
      return;
    }

    // Convert http(s) URL to ws(s) URL if needed
    final wsUrl = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/ws/chat/$userId');

    try {
      final channel = _connector(uri);
      _channel = channel;

      // Cancel any existing reconnect timer if connection succeeded
      _reconnectTimer?.cancel();

      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _heardSincePing = true;

      // Listen to incoming messages from server
      channel.stream.listen(
        (data) {
          if (!identical(_channel, channel)) return;
          if (data is! String) return;
          _heardSincePing = true;
          _attempt = 0; // the link works: the next drop starts from fast again
          final decoded = jsonDecode(data) as Map<String, dynamic>;
          if (decoded['type'] != 'pong') {
            _log(
              'got ${decoded['type']}'
              '${decoded['op'] != null ? ':${decoded['op']}' : ''}'
              '${decoded['status'] != null ? ':${decoded['status']}' : ''}',
            );
          }
          if (decoded['type'] == 'pong') {
            _pongSeen = true;
            return;
          }
          if (!_events.isClosed) _events.add(decoded);
        },
        onError: (error) {
          _log('error: $error');
          if (!identical(_channel, channel)) return;
          _notifyDisconnected();
          _handleReconnect();
        },
        onDone: () {
          _log('closed (code ${channel.closeCode}, ${channel.closeReason})');
          if (!identical(_channel, channel)) return;
          _notifyDisconnected();
          _handleReconnect();
        },
      );
    } catch (_) {
      _handleReconnect();
    }
  }

  /// Lets listeners know the link dropped; the server only ever announces
  /// 'connected', so without this the UI would claim to be online forever.
  void _notifyDisconnected() {
    if (_isExplicitDisconnect || _events.isClosed) return;
    _events.add({'type': 'status', 'status': 'disconnected'});
  }

  /// Tries again after the next wait in [backoff].
  void _handleReconnect() {
    if (_isExplicitDisconnect) return;

    _reconnectTimer?.cancel();
    final wait =
        backoff[_attempt < backoff.length ? _attempt : backoff.length - 1];
    _attempt++;
    _reconnectTimer = Timer(wait, _open);
  }

  /// Replaces the link right now, skipping any waiting.
  void reconnectNow() {
    if (_isExplicitDisconnect || _lastUserId == null) return;
    _reconnectTimer?.cancel();
    _attempt = 0;
    _notifyDisconnected();
    _open();
  }

  /// Asks the server to prove the link is alive.
  void _ping() {
    if (_channel == null || _isExplicitDisconnect) return;
    _heardSincePing = false;
    sendMessage({'type': 'ping'});
    if (!_pongSeen) return; // an older server never answers: do not judge it
    _deadline?.cancel();
    _deadline = Timer(heartbeatTimeout, () {
      if (!_heardSincePing) reconnectNow();
    });
  }

  /// The app went to the background.
  void onAppPaused() => _pausedAt = _clock();

  /// The app is back. A link that sat through a long absence is replaced at
  /// once; after a short one it is just checked.
  void onAppResumed() {
    if (_isExplicitDisconnect || _lastUserId == null) return;
    final away = _pausedAt == null
        ? Duration.zero
        : _clock().difference(_pausedAt!);
    _pausedAt = null;
    if (_channel == null || away >= awayLongEnough) {
      reconnectNow();
    } else {
      _ping();
    }
  }

  /// Sends a message payload to the server
  bool sendMessage(Map<String, dynamic> payload) {
    final note =
        '${payload['type']}'
        '${payload['op'] != null ? ':${payload['op']}' : ''}';
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(payload));
        if (payload['type'] != 'ping' && payload['op'] != 'stroke') {
          _log('sent $note');
        }
        return true;
      } catch (e) {
        _log('send FAILED $note: $e');
        return false;
      }
    }
    _log('send DROPPED $note (no connection)');
    return false;
  }

  /// Closes the link and stops reconnecting (someone signed out), but keeps
  /// [events] open for whoever signs in next.
  void close() {
    _isExplicitDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    _deadline?.cancel();
    _channel?.sink.close();
    _channel = null;
    _lastUserId = null;
  }

  /// Disconnects the socket explicitly (stops auto-reconnect)
  void disconnect() {
    _isExplicitDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    _deadline?.cancel();
    _channel?.sink.close();
    _events.close();
    _channel = null;
  }
}
