// lib/src/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Supplies a currently valid access token, refreshing first if needed.
/// Called on every (re)connect because tokens expire between reconnects.
typedef TokenProvider = Future<String?> Function();

class WebSocketService {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  Timer? _reconnectTimer;

  String? _lastBaseUrl;
  String? _lastUserId;
  TokenProvider? _tokenProvider;
  bool _isExplicitDisconnect = false;

  /// Returns a stream of incoming WebSocket JSON messages
  Stream<Map<String, dynamic>>? get messageStream => _controller?.stream;

  /// Connects to the FastAPI WebSocket endpoint and authenticates.
  ///
  /// The server ignores the user id in the URL until the first frame proves it
  /// with an access token.
  void connect(String baseUrl, String userId, TokenProvider tokenProvider) {
    _lastBaseUrl = baseUrl;
    _lastUserId = userId;
    _tokenProvider = tokenProvider;
    _isExplicitDisconnect = false;

    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
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

    String? token;
    try {
      token = await tokenProvider();
    } catch (_) {
      token = null;
    }
    if (_isExplicitDisconnect) return;
    if (token == null || token.isEmpty) {
      _handleReconnect();
      return;
    }

    // Convert http(s) URL to ws(s) URL if needed
    final wsUrl = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/ws/chat/$userId');

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      // Cancel any existing reconnect timer if connection succeeded
      _reconnectTimer?.cancel();

      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));

      // Listen to incoming messages from server
      channel.stream.listen(
        (data) {
          if (data is String) {
            final decoded = jsonDecode(data) as Map<String, dynamic>;
            _controller?.add(decoded);
          }
        },
        onError: (error) {
          if (!identical(_channel, channel)) return;
          _notifyDisconnected();
          _handleReconnect();
        },
        onDone: () {
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
    if (_isExplicitDisconnect) return;
    _controller?.add({'type': 'status', 'status': 'disconnected'});
  }

  /// Automatically tries to reconnect every 5 seconds when connection drops
  void _handleReconnect() {
    if (_isExplicitDisconnect) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _open);
  }

  /// Sends a message payload to the server
  bool sendMessage(Map<String, dynamic> payload) {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(payload));
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Disconnects the socket explicitly (stops auto-reconnect)
  void disconnect() {
    _isExplicitDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _controller?.close();
    _channel = null;
    _controller = null;
  }
}
