import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/chat_message.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// A single message model for the thread UI.

/// Real-time Chat thread screen wired with Riverpod and WebSockets.
class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.contactName,
    required this.recipientId,
    this.isGroup = false,
    this.onBack,
  });

  final String contactName;
  final String recipientId;
  final bool isGroup;
  final VoidCallback? onBack;

  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Trigger message sending via ChatViewModel and WebSocket service
    ref
        .read(chatViewModelProvider.notifier)
        .sendMessage(recipientId: widget.recipientId, content: text);

    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatViewModelProvider);
    final currentUser = ref.watch(currentUserProvider);

    // Map raw incoming WebSocket messages into ChatMessage objects for display
    final currentUserId = currentUser?.id?.toString();

    final List<ChatMessage> messages = chatState.messages.map((msg) {
      final isOutgoing =
          currentUserId != null &&
          msg['sender_id']?.toString() == currentUserId;
      final senderName = isOutgoing ? 'You' : widget.contactName;
      final timeStr = msg['timestamp'] != null
          ? DateTime.tryParse(
                  msg['timestamp'],
                )?.toLocal().toString().substring(11, 16) ??
                ''
          : '';

      return ChatMessage(
        who: timeStr.isNotEmpty ? '$senderName · $timeStr' : senderName,
        // fall back to alternate keys in case the optimistic append uses a
        // different field name than the real socket payload
        text: (msg['content'] ?? msg['text'] ?? msg['message'] ?? '') as String,
        side: isOutgoing ? ChatBubbleSide.outgoing : ChatBubbleSide.incoming,
      );
    }).toList();

    return SafeArea(
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppTopBar(
          onBack: widget.onBack ?? () => Navigator.of(context).pop(),
          titleFontSize: 15,
          title: widget.contactName,
          trailing: AvatarThumb(size: 28, isGroup: widget.isGroup),
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: _StatusLine(),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final m = messages[index];
                  return ChatBubble(who: m.who, message: m.text, side: m.side);
                },
              ),
            ),
            ChatInputBar(controller: _controller, onSend: _handleSend),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft, width: 1)),
      ),
      child: const Text(
        'COMM-LINK ESTABLISHED · 22:04 STARDATE',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 9,
          color: AppColors.textDim,
        ),
      ),
    );
  }
}
