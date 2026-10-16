import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/data/services/attachment_download_service.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/message_actions.dart';
import 'package:serafim/src/utils/chat/swipe_to_reply.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.contactName,
    required this.recipientId,
    this.username,
    this.profilePic,
    this.isGroup = false,
    this.onBack,
  });

  final String contactName;
  final String recipientId;
  final String? username;
  final String? profilePic;
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

  /// A photo is being prepared and sent.
  bool _attaching = false;

  /// The message being replied to, while composing.
  LocalMessage? _replyingTo;

  /// One key per message so a quote can scroll to its original.
  final Map<String, GlobalKey> _itemKeys = {};

  late final ActiveRoomNotifier _activeRoom;
  String? _registeredRoom;

  @override
  void initState() {
    super.initState();
    _activeRoom = ref.read(activeRoomProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Tell alerts this conversation is on screen...
      _registeredRoom = _roomId;
      _activeRoom.set(_registeredRoom);
      // ...and opening it counts as reading what's already in it.
      _markRead();
    });
  }

  void _markRead() {
    if (!mounted) return;
    ref.read(chatViewModelProvider.notifier).markRoomRead(_roomId);
  }

  Future<void> _handleAttach() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    if (_attaching) return;
    final quality = ref.read(settingsProvider).imageQuality;
    try {
      final bytes = await pickShrunkImage(
        context,
        maxSide: quality.maxSide,
        quality: quality.jpegQuality,
        // From here until the message is saved, show a spinner.
        onPicked: () {
          if (mounted) setState(() => _attaching = true);
        },
      );
      if (bytes == null || !mounted) return;

      await ref
          .read(chatViewModelProvider.notifier)
          .sendMessage(
            roomId: _roomId,
            recipientId: widget.recipientId,
            imageBytes: bytes,
            replyToId: _replyingTo?.messageId,
          );
      if (mounted) setState(() => _replyingTo = null);
      _scheduleScrollToBottom();
    } catch (error) {
      _toast(
        humanError(error, fallback: "Couldn't send that photo."),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  @override
  void dispose() {
    final room = _registeredRoom;
    if (room != null) {
      // Not during the unmount itself: that would rebuild listeners while the
      // tree is locked.
      final notifier = _activeRoom;
      Future.microtask(() => notifier.clear(room));
    }
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

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.rust : null,
        ),
      );
  }

  /// Exports a received/sent image to the gallery or Downloads folder.
  Future<void> _saveImage(LocalMessage message, String senderLabel) async {
    final path = message.localMediaPath;
    if (path == null) return;

    _toast('Saving image…');
    try {
      final where = await ref
          .read(attachmentDownloadServiceProvider)
          .saveImage(path, senderLabel: senderLabel, sentAt: message.timestamp);
      _toast(where);
    } on AttachmentSaveException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not save the image.', error: true);
    }
  }

  Future<void> _showMessageActions(
    LocalMessage message, {
    required bool isOutgoing,
    required String senderLabel,
  }) async {
    if (message.isDeleted) return;

    final text = message.textContent ?? '';
    final isImage =
        message.type == MessageType.image && message.localMediaPath != null;
    final isConfirmed =
        message.status != MessageStatus.sending &&
        message.status != MessageStatus.failed;

    final actions = availableMessageActions(
      isOutgoing: isOutgoing,
      isDeleted: message.isDeleted,
      hasText: text.isNotEmpty,
      isImage: isImage,
      isConfirmed: isConfirmed,
    );
    if (actions.isEmpty) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (ctx) {
        Widget tile(IconData icon, String label, String value) => ListTile(
          leading: Icon(icon, size: 20, color: AppColors.text),
          title: Text(
            label,
            style: AppTextStyles.body.copyWith(color: AppColors.text),
          ),
          onTap: () => Navigator.pop(ctx, value),
        );

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in actions)
                switch (a) {
                  MessageAction.copy => tile(Icons.copy, 'Copy text', 'copy'),
                  MessageAction.download => tile(
                    Icons.download_outlined,
                    'Download image',
                    'download',
                  ),
                  MessageAction.edit => tile(
                    Icons.edit_outlined,
                    'Edit',
                    'edit',
                  ),
                  MessageAction.delete => tile(
                    Icons.delete_outline,
                    isConfirmed ? 'Delete for everyone' : 'Delete',
                    'delete',
                  ),
                },
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        _toast('Copied');
      case 'download':
        await _saveImage(message, senderLabel);
      case 'edit':
        await _editMessage(message);
      case 'delete':
        await _deleteFlow(
          message,
          isOutgoing: isOutgoing,
          isConfirmed: isConfirmed,
        );
    }
  }

  Future<void> _editMessage(LocalMessage message) async {
    final controller = TextEditingController(text: message.textContent ?? '');
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Edit message',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: 4000,
          style: AppTextStyles.fieldInput,
          cursorColor: AppColors.primary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newText == null || newText.trim() == (message.textContent ?? '')) {
      return;
    }
    final error = await ref
        .read(chatViewModelProvider.notifier)
        .editMessage(message.messageId, newText);
    if (error != null) _toast(error, error: true);
  }

  /// Asks how to delete: for me, or (own sent messages) for everyone.
  Future<void> _deleteFlow(
    LocalMessage message, {
    required bool isOutgoing,
    required bool isConfirmed,
  }) async {
    final options = deleteOptionsFor(
      isOutgoing: isOutgoing,
      isDeleted: message.isDeleted,
      isConfirmed: isConfirmed,
    );
    final isImage = message.type == MessageType.image;
    final what = isImage ? 'image' : 'message';

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Delete $what?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          options.forEveryone
              ? '"Delete for me" removes it from this device only. "Delete for '
                    'everyone" removes it for everyone in the conversation and '
                    "can't be undone."
              : isOutgoing && !isConfirmed
              ? 'This $what was never delivered. It will be removed from this '
                    'device.'
              : 'It will be removed from this device. ${widget.contactName} '
                    'keeps their copy.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'me'),
            child: Text(options.forEveryone ? 'Delete for me' : 'Delete'),
          ),
          if (options.forEveryone)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'everyone'),
              child: const Text('Delete for everyone'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final vm = ref.read(chatViewModelProvider.notifier);
    if (choice == 'everyone') {
      final error = await vm.deleteMessage(message.messageId);
      if (error != null) _toast(error, error: true);
    } else if (isOutgoing && !isConfirmed) {
      // Never reached the server: remove it outright.
      await vm.deleteMessage(message.messageId);
    } else {
      await vm.deleteForMe(message.messageId);
    }
    if (_replyingTo?.messageId == message.messageId) {
      setState(() => _replyingTo = null);
    }
  }

  // ---- replying ----

  bool _canReplyTo(LocalMessage m) =>
      !m.isDeleted &&
      m.status != MessageStatus.sending &&
      m.status != MessageStatus.failed;

  String _snippetOf(LocalMessage m) {
    if (m.isDeleted) return 'Message deleted';
    final text = (m.textContent ?? '').trim();
    if (m.type == MessageType.image) {
      return text.isEmpty ? '📷 Photo' : '📷 $text';
    }
    return text;
  }

  void _startReply(LocalMessage message) {
    if (!_canReplyTo(message)) {
      _toast(
        message.isDeleted
            ? "You can't reply to a deleted message."
            : 'Wait until the message has been sent to reply to it.',
      );
      return;
    }
    setState(() => _replyingTo = message);
  }

  ReplyQuoteData? _quoteFor(
    LocalMessage message,
    Map<String, LocalMessage> byId,
    String? myId,
  ) {
    final targetId = message.replyToId;
    if (targetId == null) return null;

    final original = byId[targetId];
    if (original == null) {
      return const ReplyQuoteData(
        author: 'Original message',
        snippet: 'No longer available',
        available: false,
      );
    }
    return ReplyQuoteData(
      author: original.senderId == myId ? 'You' : widget.contactName,
      snippet: _snippetOf(original),
      available: !original.isDeleted,
      onTap: () => _scrollToMessage(targetId),
    );
  }

  void _scrollToMessage(String messageId) {
    final context = _itemKeys[messageId]?.currentContext;
    if (context == null) {
      _toast('Scroll up to find the original message.');
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
          replyToId: _replyingTo?.messageId,
        );

    _messageController.clear();
    if (_replyingTo != null) setState(() => _replyingTo = null);

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

    // We're looking at this conversation, so anything incoming is read.
    final myId = _currentUserId;
    final hasUnread = currentMessages.any(
      (m) => m.recipientId == myId && m.status != MessageStatus.read,
    );
    if (hasUnread) _markRead();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?.id;

    final roomId = currentUserId != null
        ? ChatViewModel.buildRoomId(currentUserId, widget.recipientId)
        : widget.recipientId;

    final messagesProvider = roomMessagesStreamProvider(roomId);

    // React to actual message additions instead of calling scroll
    // from inside the widget's build process.
    ref.listen<AsyncValue<List<LocalMessage>>>(
      messagesProvider,
      _handleMessagesChanged,
    );

    final messagesAsync = ref.watch(messagesProvider);

    // Attachments are friends-only. The button explains why it is off; the
    // server refuses them regardless.
    final friendsAsync = ref.watch(friendsProvider);
    final isFriend = ref.watch(friendIdsProvider).contains(widget.recipientId);
    final attachDisabledReason = isFriend
        ? null
        : friendsAsync.isLoading
        ? 'Checking whether you are friends…'
        : 'Attachments are only available between friends. '
              'Add ${widget.contactName} as a friend to share images.';

    return Scaffold(
      backgroundColor: AppColors.paper,

      appBar: AppTopBar(
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        titleFontSize: 15,
        titleWidget: Row(
          children: [
            AvatarThumb(
              size: 30,
              isGroup: widget.isGroup,
              imageProvider:
                  (widget.profilePic != null && widget.profilePic!.isNotEmpty)
                  ? NetworkImage(widget.profilePic!)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.username ?? widget.contactName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),

      // The wallpaper sits behind everything; bubbles and the input bar are
      // opaque, so it only shows in the gaps.
      body: Stack(
        children: [
          const Positioned.fill(child: ChatBackground()),
          Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: _StatusLine(),
              ),

              Expanded(
                child: messagesAsync.when(
                  loading: () {
                    return Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  },

                  error: (error, stack) {
                    return Center(
                      child: Text(
                        humanError(
                          error,
                          fallback: "Couldn't load this conversation.",
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.rustPale),
                      ),
                    );
                  },

                  data: (messages) {
                    if (messages.isEmpty) {
                      return const _EmptyChat();
                    }

                    final orderedMessages = _sortMessagesOldestFirst(messages);
                    final byId = {
                      for (final m in orderedMessages) m.messageId: m,
                    };

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

                        final senderLabel =
                            (isOutgoing
                                ? 'You · $time'
                                : '${widget.contactName} · $time') +
                            (message.editedAt != null && !message.isDeleted
                                ? ' · edited'
                                : '');
                        final who = isOutgoing ? 'you' : widget.contactName;

                        final bubble = ChatBubble(
                          who: senderLabel,
                          quote: _quoteFor(message, byId, currentUserId),
                          message: message.textContent ?? '',
                          imagePath: message.type == MessageType.image
                              ? message.localMediaPath
                              : null,
                          side: isOutgoing
                              ? ChatBubbleSide.outgoing
                              : ChatBubbleSide.incoming,
                          status: isOutgoing
                              ? _mapStatus(message.status)
                              : null,
                          deleted: message.isDeleted,
                          onLongPress: () => _showMessageActions(
                            message,
                            isOutgoing: isOutgoing,
                            senderLabel: who,
                          ),
                          onSaveImage: () => _saveImage(message, who),
                          onDeleteImage: () => _deleteFlow(
                            message,
                            isOutgoing: isOutgoing,
                            isConfirmed:
                                message.status != MessageStatus.sending &&
                                message.status != MessageStatus.failed,
                          ),
                        );

                        return KeyedSubtree(
                          key: _itemKeys.putIfAbsent(
                            message.messageId,
                            GlobalKey.new,
                          ),
                          child: SwipeToReply(
                            enabled: !message.isDeleted,
                            onReply: () => _startReply(message),
                            child: bubble,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              ChatInputBar(
                controller: _messageController,
                onSend: _handleSend,
                onAttach: _handleAttach,
                attachDisabledReason: attachDisabledReason,
                attachBusy: _attaching,
                replyPreview: _replyingTo == null
                    ? null
                    : (
                        author: _replyingTo!.senderId == currentUserId
                            ? 'yourself'
                            : widget.contactName,
                        snippet: _snippetOf(_replyingTo!),
                        onCancel: () => setState(() => _replyingTo = null),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
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
      decoration: BoxDecoration(
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
