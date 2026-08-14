// lib/src/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;

  /// Returns a stream of incoming WebSocket JSON messages
  Stream<Map<String, dynamic>>? get messageStream => _controller?.stream;

  /// Connects to the FastAPI WebSocket endpoint
  void connect(String baseUrl, String userId) {
    // Convert http(s) URL to ws(s) URL if needed
    final wsUrl = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');

    final uri = Uri.parse('$wsUrl/ws/chat/$userId');

    _channel = WebSocketChannel.connect(uri);
    _controller = StreamController<Map<String, dynamic>>.broadcast();

    // Listen to incoming messages from server
    _channel!.stream.listen(
      (data) {
        if (data is String) {
          final decoded = jsonDecode(data) as Map<String, dynamic>;
          _controller?.add(decoded);
        }
      },
      onError: (error) {
        _controller?.addError(error);
      },
      onDone: () {
        print('WebSocket connection closed.');
      },
    );
  }

  /// Sends a message payload to the server
  void sendMessage(Map<String, dynamic> payload) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(payload));
    }
  }

  /// Disconnects the socket
  void disconnect() {
    _channel?.sink.close();
    _controller?.close();
    _channel = null;
    _controller = null;
  }
}
