// lib/src/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  Timer? _reconnectTimer;

  String? _lastBaseUrl;
  String? _lastUserId;
  bool _isExplicitDisconnect = false;

  /// Returns a stream of incoming WebSocket JSON messages
  Stream<Map<String, dynamic>>? get messageStream => _controller?.stream;

  /// Connects to the FastAPI WebSocket endpoint
  void connect(String baseUrl, String userId) {
    _lastBaseUrl = baseUrl;
    _lastUserId = userId;
    _isExplicitDisconnect = false;

    _controller ??= StreamController<Map<String, dynamic>>.broadcast();

    // Convert http(s) URL to ws(s) URL if needed
    final wsUrl = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');

    final uri = Uri.parse('$wsUrl/ws/chat/$userId');

    try {
      _channel = WebSocketChannel.connect(uri);

      // Cancel any existing reconnect timer if connection succeeded
      _reconnectTimer?.cancel();

      // Listen to incoming messages from server
      _channel!.stream.listen(
        (data) {
          if (data is String) {
            final decoded = jsonDecode(data) as Map<String, dynamic>;
            _controller?.add(decoded);
          }
        },
        onError: (error) {
          _handleReconnect();
        },
        onDone: () {
          _handleReconnect();
        },
      );
    } catch (_) {
      _handleReconnect();
    }
  }

  /// Automatically tries to reconnect every 5 seconds when connection drops
  void _handleReconnect() {
    if (_isExplicitDisconnect) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_lastBaseUrl != null && _lastUserId != null) {
        connect(_lastBaseUrl!, _lastUserId!);
      }
    });
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
