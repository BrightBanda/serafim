import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

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

/// Converts the database message status into the status expected by
/// [ChatBubble].
ChatMessageStatus _mapStatus(MessageStatus status) {
  switch (status) {
    case MessageStatus.sending:
      return ChatMessageStatus.sending;

    case MessageStatus.sent:
      return ChatMessageStatus.sent;

    case MessageStatus.delivered:
      return ChatMessageStatus.delivered;

    case MessageStatus.read:
      return ChatMessageStatus.read;

    case MessageStatus.failed:
      return ChatMessageStatus.failed;
  }
}

/// Sorts messages chronologically.
///
/// We do not depend on the ordering of the Isar query/stream.
/// The timestamp is the primary ordering key and the local Isar ID is
/// used as a deterministic tie-breaker.
List<LocalMessage> _sortMessagesOldestFirst(List<LocalMessage> messages) {
  final sorted = [...messages];

  sorted.sort((a, b) {
    final timestampComparison = a.timestamp.compareTo(b.timestamp);

    if (timestampComparison != 0) {
      return timestampComparison;
    }

    return a.id.compareTo(b.id);
  });

  return sorted;
}

/// Formats a DateTime as HH:mm without relying on String.substring().
String _formatMessageTime(BuildContext context, DateTime timestamp) {
  final localTime = timestamp.toLocal();

  final timeOfDay = TimeOfDay.fromDateTime(localTime);

  return timeOfDay.format(context);
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _initialScrollDone = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _currentUserId {
    return ref.read(currentUserProvider)?.id;
  }

  String get _roomId {
    final userId = _currentUserId;

    if (userId == null) {
      return widget.recipientId;
    }

    return ChatViewModel.buildRoomId(userId, widget.recipientId);
  }

  void _handleSend() {
    final content = _messageController.text.trim();

    if (content.isEmpty) {
      return;
    }

    final currentUser = ref.read(currentUserProvider);

    if (currentUser == null) {
      return;
    }

    ref
        .read(chatViewModelProvider.notifier)
        .sendMessage(
          roomId: ChatViewModel.buildRoomId(currentUser.id, widget.recipientId),
          recipientId: widget.recipientId,
          content: content,
        );

    _messageController.clear();

    // The message is written to Isar before the socket send,
    // so the stream will update and the scroll will happen.
    _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final maxScroll = _scrollController.position.maxScrollExtent;

      if (animated) {
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(maxScroll);
      }
    });
  }

  void _handleMessagesChanged(
    AsyncValue<List<LocalMessage>>? previous,
    AsyncValue<List<LocalMessage>> next,
  ) {
    final previousMessages = previous?.value;
    final currentMessages = next.value;

    if (currentMessages == null) {
      return;
    }

    final previousCount = previousMessages?.length ?? 0;
    final currentCount = currentMessages.length;

    // A message was added.
    if (currentCount > previousCount) {
      _scheduleScrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?.id;

    final messagesProvider = roomMessagesStreamProvider(_roomId);
    ref.listen<AsyncValue<List<LocalMessage>>>(
      messagesProvider,
      _handleMessagesChanged,
    );

    final messagesAsync = ref.watch(messagesProvider);

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
                loading: () {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                },

                error: (error, stack) {
                  return Center(
                    child: Text(
                      'Failed to load messages: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                },

                data: (messages) {
                  if (messages.isEmpty) {
                    return const _EmptyChat();
                  }

                  final orderedMessages = _sortMessagesOldestFirst(messages);

                  // Scroll to the bottom only once when the conversation
                  // is initially loaded.
                  if (!_initialScrollDone) {
                    _initialScrollDone = true;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_scrollController.hasClients) {
                        return;
                      }

                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                    });
                  }

                  return ListView.separated(
                    controller: _scrollController,

                    padding: const EdgeInsets.all(14),

                    itemCount: orderedMessages.length,

                    separatorBuilder: (_, __) {
                      return const SizedBox(height: 10);
                    },

                    itemBuilder: (context, index) {
                      final message = orderedMessages[index];

                      final isOutgoing =
                          currentUserId != null &&
                          message.senderId == currentUserId;

                      final time = _formatMessageTime(
                        context,
                        message.timestamp,
                      );

                      final senderLabel = isOutgoing
                          ? 'You · $time'
                          : '${widget.contactName} · $time';

                      return ChatBubble(
                        who: senderLabel,
                        message: message.textContent ?? '',
                        side: isOutgoing
                            ? ChatBubbleSide.outgoing
                            : ChatBubbleSide.incoming,
                        status: isOutgoing ? _mapStatus(message.status) : null,
                      );
                    },
                  );
                },
              ),
            ),

            ChatInputBar(controller: _messageController, onSend: _handleSend),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No messages yet. Say hi!',
        style: TextStyle(color: AppColors.textDim),
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
