// lib/src/presentation/view/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';

class ChatTestScreen extends ConsumerStatefulWidget {
  final String recipientId;
  final String recipientName;

  const ChatTestScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  ConsumerState<ChatTestScreen> createState() => _ChatTestScreenState();
}

class _ChatTestScreenState extends ConsumerState<ChatTestScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    ref
        .read(chatViewModelProvider.notifier)
        .sendMessage(recipientId: widget.recipientId, content: text);

    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatViewModelProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.recipientName)),
      body: Column(
        children: [
          // Message List
          Expanded(
            child: ListView.builder(
              itemCount: chatState.messages.length,
              itemBuilder: (context, index) {
                final msg = chatState.messages[index];
                return ListTile(
                  title: Text(msg['content'] ?? ''),
                  subtitle: Text(msg['sender_id'] ?? ''),
                );
              },
            ),
          ),
          // Input Box
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _onSend),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
