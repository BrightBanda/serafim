// lib/src/providers/websocket_providers.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/providers/app_providers.dart'; // Contains appConfigProvider
import 'package:serafim/src/providers/auth_providers.dart'; // Contains currentUserProvider
import 'package:serafim/src/providers/network_providers.dart';

/// Singleton instance of the WebSocketService
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();

  // Coming back to the app is when a dead link must be replaced, so a message
  // that arrived meanwhile shows up at once.
  final observer = _ResumeObserver(service);
  try {
    WidgetsBinding.instance.addObserver(observer);
  } catch (_) {
    // No Flutter binding (a plain unit test): nothing to observe.
  }

  // Clean up when the provider is disposed
  ref.onDispose(() {
    try {
      WidgetsBinding.instance.removeObserver(observer);
    } catch (_) {}
    service.disconnect();
  });

  return service;
});

/// Keeps the chat connection open for whoever is signed in, and gives the
/// stream of everything the server sends.
///
/// The stream belongs to the service and outlives reconnects. Subscribe to it
/// directly (see ChatViewModel) rather than through `ref.listen`: Riverpod
/// pauses listeners of screens that are covered by another page, and a paused
/// listener would hold live frames — a Draw Together answer, a typing
/// indicator — until that page closed.
final webSocketEventsProvider = Provider<Stream<Map<String, dynamic>>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  final config = ref.watch(appConfigProvider);
  final wsService = ref.watch(webSocketServiceProvider);

  if (currentUser == null) {
    // Signed out: nobody's frames should arrive any more.
    wsService.close();
    return wsService.events;
  }

  // Connect using backend URL and current user ID
  final store = ref.read(sessionStoreProvider);
  final dio = ref.read(apiDioProvider);

  // A fresh token for every (re)connect. When the stored one has expired, a
  // cheap authenticated call makes the API interceptor refresh it (it
  // single-flights refreshes, which a second refresh path here would break).
  Future<String?> freshToken() async {
    if (store.current == null || store.current!.isExpired) {
      try {
        await dio.get<dynamic>('/auth/me');
      } catch (_) {}
    }
    return store.current?.accessToken;
  }

  wsService.connect(config.apiBaseUrl, currentUser.id, freshToken);

  return wsService.events;
});

/// Tells the socket when the app leaves and returns.
class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._service);

  final WebSocketService _service;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _service.onAppPaused();
      case AppLifecycleState.resumed:
        _service.onAppResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}
