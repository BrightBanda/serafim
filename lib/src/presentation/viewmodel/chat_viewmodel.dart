// lib/src/presentation/viewmodel/chat_view_model.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';

class ChatState {
  final List<Map<String, dynamic>> messages;
  final bool isConnected;

  const ChatState({this.messages = const [], this.isConnected = false});

  ChatState copyWith({
    List<Map<String, dynamic>>? messages,
    bool? isConnected,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class ChatViewModel extends Notifier<ChatState> {
  @override
  ChatState build() {
    // Listen to incoming WebSocket messages stream
    ref.listen<AsyncValue<Map<String, dynamic>>>(webSocketStreamProvider, (
      previous,
      next,
    ) {
      next.whenData((messageData) {
        _handleIncomingMessage(messageData);
      });
    });

    return const ChatState();
  }

  void _handleIncomingMessage(Map<String, dynamic> data) {
    // Update local state with incoming server message or status
    state = state.copyWith(messages: [...state.messages, data]);
  }

  /// Send a chat message through WebSocket
  void sendMessage({required String recipientId, required String content}) {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final payload = {
      "recipient_id": recipientId,
      "content": content,
      "timestamp": DateTime.now().toIso8601String(),
    };

    // Send payload through WebSocket Service
    ref.read(webSocketServiceProvider).sendMessage(payload);
  }
}

final chatViewModelProvider = NotifierProvider<ChatViewModel, ChatState>(
  ChatViewModel.new,
);
