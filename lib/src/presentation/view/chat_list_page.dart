import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/user_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_row.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ChatPreview {
  const ChatPreview({
    required this.id,
    required this.name,
    required this.preview,
    required this.time,
    this.isGroup = false,
    this.unread = false,
  });

  final String id;
  final String name;
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
                return ChatRow(
                  name: chat.name,
                  preview: chat.preview,
                  time: chat.time,
                  isGroup: chat.isGroup,
                  unread: chat.unread,
                  onTap: () => onOpenChat?.call(chat),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
