import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_row.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// Conversations: your friends, plus anyone you have exchanged messages with.
/// New people are found in Discover.
class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key, this.onSearch});

  /// Overrides what the search button does; by default it opens Discover.
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final friendsAsync = ref.watch(friendsProvider);
    final peersAsync = ref.watch(conversationPeerIdsProvider);

    void openDiscover() =>
        ref.read(navigationNotifierProvider.notifier).setIndex(1);

    final friends = friendsAsync.value ?? const <PublicUser>[];
    final friendIds = {for (final f in friends) f.id};
    final strangers = (peersAsync.value ?? const <String>[])
        .where((id) => !friendIds.contains(id))
        .toList();

    final stillLoading =
        (friendsAsync.isLoading && !friendsAsync.hasValue) ||
        (peersAsync.isLoading && !peersAsync.hasValue);

    Widget body;
    if (currentUser == null || stillLoading) {
      body = Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (friendsAsync.hasError && friends.isEmpty && strangers.isEmpty) {
      body = _CenteredMessage(
        text: 'Failed to load chats: ${friendsAsync.error}',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(friendsProvider),
      );
    } else if (friends.isEmpty && strangers.isEmpty) {
      body = _CenteredMessage(
        text: 'No conversations yet.\nFind people in Discover to start one.',
        actionLabel: 'Open Discover',
        onAction: openDiscover,
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.paperRaised,
        onRefresh: () async {
          ref.invalidate(friendsProvider);
          try {
            await ref.read(friendsProvider.future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('CHAT', style: AppTextStyles.eyebrow),
            ),
            for (final user in friends) ...[
              _ChatListItem(user: user, myId: currentUser.id),
              const SizedBox(height: 10),
            ],
            for (final id in strangers) ...[
              _PeerChatItem(peerId: id, myId: currentUser.id),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        trailing: GestureDetector(
          onTap: onSearch ?? openDiscover,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.paper,
              border: Border.all(color: AppColors.lineSoft, width: 1.5),
            ),
            child: Icon(Icons.search, size: 14, color: AppColors.textDim),
          ),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: AppTextStyles.body),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel, style: AppTextStyles.linkText),
            ),
          ],
        ),
      ),
    );
  }
}

/// Someone you have messaged who is not (or is no longer) a friend: their
/// profile is fetched by id.
class _PeerChatItem extends ConsumerWidget {
  const _PeerChatItem({required this.peerId, required this.myId});

  final String peerId;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(publicUserProvider(peerId));
    return user.when(
      data: (u) => _ChatListItem(user: u, myId: myId),
      // Keep the row so the conversation is never hidden by a failed lookup.
      error: (_, __) => _ChatListItem(
        user: PublicUser(
          id: peerId,
          username: 'unknown',
          displayName: 'Unknown user',
        ),
        myId: myId,
      ),
      loading: () => SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One conversation row, fed by the latest local message in its room.
class _ChatListItem extends ConsumerWidget {
  const _ChatListItem({required this.user, required this.myId});

  final PublicUser user;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomId = ChatViewModel.buildRoomId(myId, user.id);
    final summary = ref
        .watch(roomSummaryProvider((roomId: roomId, myId: myId)))
        .value;
    final latest = summary?.latest;

    var preview = 'Tap to start conversation';
    var time = '';
    if (latest != null) {
      final text = latest.textContent ?? '';
      final body = latest.isDeleted
          ? 'Message deleted'
          : latest.type == MessageType.image
          ? (text.isEmpty ? '📷 Photo' : '📷 $text')
          : text;
      preview = latest.senderId == myId ? 'You: $body' : body;
      time = formatChatListTime(context, latest.timestamp);
    }

    return ChatRow(
      name: user.displayName,
      preview: preview,
      time: time,
      unread: (summary?.unreadCount ?? 0) > 0,
      imageProvider: avatarImage(user.profilePic),
      onTap: () => openChatWith(context, user),
    );
  }
}
