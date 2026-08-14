// lib/src/providers/websocket_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/providers/app_providers.dart'; // Contains appConfigProvider
import 'package:serafim/src/providers/auth_providers.dart'; // Contains currentUserProvider

/// Singleton instance of the WebSocketService
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();

  // Clean up when the provider is disposed
  ref.onDispose(() {
    service.disconnect();
  });

  return service;
});

/// Auto-connects WebSocket when user is authenticated and yields incoming JSON streams
final webSocketStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  final config = ref.watch(appConfigProvider);
  final wsService = ref.watch(webSocketServiceProvider);

  if (currentUser == null) {
    return const Stream.empty();
  }

  // Connect using backend URL and current user ID
  wsService.connect(config.apiBaseUrl, currentUser.id);

  return wsService.messageStream ?? const Stream.empty();
});
