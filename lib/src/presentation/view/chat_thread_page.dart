import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// Real-time Chat thread screen wired with Riverpod, local-first Isar
/// storage, and WebSockets.
///
/// Messages are never rendered straight from the socket — the socket only
/// writes to Isar (via [ChatViewModel]), and this screen watches Isar
/// directly. That means: sends appear instantly (optimistic local write),
/// history survives app restarts, and there's a single source of truth for
/// what's on screen.
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

    // 1:1 chat for now — roomId and recipientId are the same. Revisit this
    // once group chats need a roomId distinct from any single participant.
    ref
        .read(chatViewModelProvider.notifier)
        .sendMessage(
          roomId: widget.recipientId,
          recipientId: widget.recipientId,
          content: text,
        );

    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      roomMessagesStreamProvider(widget.recipientId),
    );
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?.id;

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
              child: messagesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (error, stack) => Center(
                  child: Text(
                    'Failed to load messages: $error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                data: (localMessages) {
                  if (localMessages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet. Say hi!',
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    );
                  }

                  // watchMessagesForRoom sorts newest-first; reverse for a
                  // natural top-to-bottom chat read order.
                  final ordered = localMessages.reversed.toList();

                  return ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: ordered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final m = ordered[index];
                      final isOutgoing =
                          currentUserId != null && m.senderId == currentUserId;
                      final timeStr = m.timestamp
                          .toLocal()
                          .toString()
                          .substring(11, 16);
                      final who = isOutgoing
                          ? 'You · $timeStr'
                          : '${widget.contactName} · $timeStr';

                      return ChatBubble(
                        who: who,
                        message: m.textContent ?? '',
                        side: isOutgoing
                            ? ChatBubbleSide.outgoing
                            : ChatBubbleSide.incoming,
                      );
                    },
                  );
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

class _StatusLine extends ConsumerWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(chatViewModelProvider).isConnected;

    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft, width: 1)),
      ),
      child: Text(
        isConnected ? 'COMM-LINK ESTABLISHED' : 'COMM-LINK OFFLINE',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 9,
          color: isConnected ? AppColors.textDim : Colors.red.shade300,
        ),
      ),
    );
  }
}
