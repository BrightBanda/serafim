import 'dart:async';

import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_search_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat/chat_row.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// Conversations: your friends, plus anyone you have exchanged messages with.
/// The search button searches both those people and the text of your messages;
/// new people are found in Discover.
class ChatListPage extends ConsumerStatefulWidget {
  const ChatListPage({super.key});

  @override
  ConsumerState<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends ConsumerState<ChatListPage> {
  static const _debounce = Duration(milliseconds: 250);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _timer;

  bool _searching = false;

  /// The debounced, trimmed query that drives the results.
  String _query = '';

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (_searching) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      } else {
        _timer?.cancel();
        _controller.clear();
        _query = '';
        _focus.unfocus();
      }
    });
  }

  void _onChanged(String value) {
    setState(() {}); // Shows or hides the clear button.
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    setState(() => _query = '');
    _focus.requestFocus();
  }

  void _openDiscover() {
    _toggleSearchOff();
    ref.read(navigationNotifierProvider.notifier).setIndex(1);
  }

  void _toggleSearchOff() {
    if (_searching) _toggleSearch();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final friendsAsync = ref.watch(friendsProvider);
    final peersAsync = ref.watch(conversationPeerIdsProvider);

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
    } else if (_searching && _query.isNotEmpty) {
      body = _SearchResults(
        query: _query,
        myId: currentUser.id,
        onOpenDiscover: _openDiscover,
      );
    } else if (friendsAsync.hasError && friends.isEmpty && strangers.isEmpty) {
      body = _CenteredMessage(
        text: humanError(
          friendsAsync.error,
          fallback: "Couldn't load your chats.",
        ),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(friendsProvider),
      );
    } else if (friends.isEmpty && strangers.isEmpty) {
      body = _CenteredMessage(
        text: 'No conversations yet.\nFind people in Discover to start one.',
        actionLabel: 'Open Discover',
        onAction: _openDiscover,
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
              child: Text(
                _searching ? 'ALL CHATS' : 'CHAT',
                style: AppTextStyles.eyebrow,
              ),
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
          onTap: _toggleSearch,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            // A bigger tap target than the visible 26px square.
            padding: const EdgeInsets.all(6),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _searching ? AppColors.primary : AppColors.paper,
                border: Border.all(
                  color: _searching ? AppColors.line : AppColors.lineSoft,
                  width: 1.5,
                ),
              ),
              child: Icon(
                _searching ? Icons.close : Icons.search,
                size: 14,
                color: _searching ? Colors.white : AppColors.textDim,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _searching
                  ? _SearchField(
                      controller: _controller,
                      focusNode: _focus,
                      onChanged: _onChanged,
                      onClear: _clear,
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                style: AppTextStyles.fieldInput.copyWith(fontSize: 12),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Search chats and messages',
                  hintStyle: AppTextStyles.fieldInput.copyWith(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: AppColors.textDim),
              ),
          ],
        ),
      ),
    );
  }
}

/// Matching people first, then individual messages, then a way out to Discover.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.myId,
    required this.onOpenDiscover,
  });

  final String query;
  final String myId;
  final VoidCallback onOpenDiscover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(chatSearchProvider(query));

    return results.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (error, _) => _CenteredMessage(
        text: humanError(error, fallback: "Couldn't search right now."),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(chatSearchProvider(query)),
      ),
      data: (found) {
        final discoverLink = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(
            child: TextButton(
              onPressed: onOpenDiscover,
              child: Text(
                'Looking for someone new? Search Discover',
                style: AppTextStyles.linkText,
              ),
            ),
          ),
        );

        if (found.isEmpty) {
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 40),
              Icon(Icons.search_off, size: 32, color: AppColors.textDim),
              const SizedBox(height: 10),
              Text(
                'No chats or messages match "$query".',
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 10),
              discoverLink,
            ],
          );
        }

        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(14),
          children: [
            if (found.people.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('CHATS', style: AppTextStyles.eyebrow),
              ),
              for (final user in found.people) ...[
                _ChatListItem(user: user, myId: myId),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
            ],
            if (found.messages.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('MESSAGES', style: AppTextStyles.eyebrow),
              ),
              for (final hit in found.messages) ...[
                _MessageHitTile(hit: hit, query: query, myId: myId),
                const SizedBox(height: 10),
              ],
            ],
            discoverLink,
          ],
        );
      },
    );
  }
}

/// One matching message: who it was with, when, and the text with the match
/// picked out. Tapping opens that conversation.
class _MessageHitTile extends StatelessWidget {
  const _MessageHitTile({
    required this.hit,
    required this.query,
    required this.myId,
  });

  final MessageHit hit;
  final String query;
  final String myId;

  @override
  Widget build(BuildContext context) {
    final message = hit.message;
    final mine = message.senderId == myId;
    final text = message.textContent ?? '';

    return GestureDetector(
      onTap: () => openChatWith(context, hit.person),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AvatarThumb(
              size: 34,
              imageProvider: avatarImage(hit.person.profilePic),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hit.person.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.text,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatChatListTime(context, message.timestamp),
                        style: AppTextStyles.fieldLabel.copyWith(fontSize: 8.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    highlightMatch(
                      mine ? 'You: $text' : text,
                      query,
                      AppTextStyles.body.copyWith(fontSize: 11),
                      AppTextStyles.body.copyWith(
                        fontSize: 11,
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.22,
                        ),
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [text] with every case-insensitive occurrence of [query] in [match] style.
TextSpan highlightMatch(
  String text,
  String query,
  TextStyle base,
  TextStyle match,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return TextSpan(text: text, style: base);

  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var from = 0;
  while (true) {
    final at = lower.indexOf(needle, from);
    if (at < 0) break;
    if (at > from)
      spans.add(TextSpan(text: text.substring(from, at), style: base));
    spans.add(
      TextSpan(text: text.substring(at, at + needle.length), style: match),
    );
    from = at + needle.length;
  }
  if (from < text.length)
    spans.add(TextSpan(text: text.substring(from), style: base));
  return TextSpan(children: spans, style: base);
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
