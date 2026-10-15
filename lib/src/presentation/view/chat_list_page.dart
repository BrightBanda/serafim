import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/user_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_row.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ChatPreview {
  const ChatPreview({
    required this.id,
    required this.name,
    required this.preview,
    required this.time,
    this.username,
    this.profilePic,
    this.isGroup = false,
    this.unread = false,
  });

  final String id;
  final String name;
  final String? username;
  final String? profilePic;
  final String preview;
  final String time;
  final bool isGroup;
  final bool unread;
}

class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key, this.onSearch, this.onOpenChat});

  final VoidCallback? onSearch;
  final ValueChanged<ChatPreview>? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(registeredUsersProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        trailing: GestureDetector(
          onTap: onSearch,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.paper,
              border: Border.all(color: AppColors.lineSoft, width: 1.5),
            ),
            child: const Icon(Icons.search, size: 14, color: AppColors.textDim),
          ),
        ),
      ),
      body: SafeArea(
        child: usersAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (error, stack) => Center(
            child: Text(
              'Failed to load users: $error',
              style: AppTextStyles.body.copyWith(color: Colors.red.shade300),
              textAlign: TextAlign.center,
            ),
          ),
          data: (users) {
            // Filter out the currently logged-in user
            final otherUsers = users
                .where((u) => u.id != currentUser?.id.toString())
                .toList();

            if (otherUsers.isEmpty) {
              return Center(
                child: Text(
                  'No other registered users found.',
                  style: AppTextStyles.body,
                ),
              );
            }

            final chats = otherUsers.map((u) {
              final nameToDisplay =
                  (u.displayName != null && u.displayName!.isNotEmpty)
                  ? u.displayName!
                  : u.email;

              return ChatPreview(
                id: u.id,
                name: nameToDisplay,
                username: u.username,
                profilePic: u.profilePic,
                preview: 'Tap to start conversation',
                time: '',
              );
            }).toList();

            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: chats.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('CHAT', style: AppTextStyles.eyebrow),
                  );
                }
                final chat = chats[index - 1];
                return _ChatListItem(chat: chat, myId: currentUser!.id);
              },
            );
          },
        ),
      ),
    );
  }
}

/// One conversation row, fed by the latest local message in its room.
class _ChatListItem extends ConsumerWidget {
  const _ChatListItem({required this.chat, required this.myId});

  final ChatPreview chat;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomId = ChatViewModel.buildRoomId(myId, chat.id);
    final summary = ref
        .watch(roomSummaryProvider((roomId: roomId, myId: myId)))
        .value;
    final latest = summary?.latest;

    var preview = chat.preview;
    var time = '';
    if (latest != null) {
      final text = latest.textContent ?? '';
      final body = latest.type == MessageType.image
          ? (text.isEmpty ? '📷 Photo' : '📷 $text')
          : text;
      preview = latest.senderId == myId ? 'You: $body' : body;
      time = formatChatListTime(context, latest.timestamp);
    }

    final pic = chat.profilePic;
    return ChatRow(
      name: chat.name,
      preview: preview,
      time: time,
      isGroup: chat.isGroup,
      unread: (summary?.unreadCount ?? 0) > 0,
      imageProvider: pic != null && pic.isNotEmpty ? NetworkImage(pic) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatThreadPage(
            contactName: chat.name,
            username: chat.username,
            profilePic: chat.profilePic,
            recipientId: chat.id,
          ),
        ),
      ),
    );
  }
}
