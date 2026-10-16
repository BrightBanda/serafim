import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
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

/// The people whose name or @username contains [query] (any case), best
/// matches first: names that *start* with it, then the rest, alphabetically.
/// Purely local: it only looks at people already on the list.
List<PublicUser> filterPeople(List<PublicUser> people, String query) {
  final needle = query.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
  if (needle.isEmpty) return List.of(people);

  int rank(PublicUser u) {
    final name = u.displayName.toLowerCase();
    final handle = u.username.toLowerCase();
    if (name.startsWith(needle) || handle.startsWith(needle)) return 0;
    if (name.contains(needle) || handle.contains(needle)) return 1;
    return 2;
  }

  final matches = people.where((u) => rank(u) < 2).toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0
          ? byRank
          : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  return matches;
}

/// One row on the chat list: a friend (whose details we have) or someone you
/// have only exchanged messages with (looked up by id).
class _Entry {
  const _Entry(this.id, this.friend);
  final String id;
  final PublicUser? friend;
}

/// Everyone on the list, most recently active first — like any messaging app.
/// People you have not messaged yet come last, alphabetically.
List<_Entry> _byRecentActivity({
  required List<PublicUser> friends,
  required List<String> strangerIds,
  required Map<String, RoomPreview> previews,
  required String myId,
}) {
  final entries = [
    for (final f in friends) _Entry(f.id, f),
    for (final id in strangerIds) _Entry(id, null),
  ];
  DateTime? lastOf(_Entry e) =>
      previews[ChatViewModel.buildRoomId(myId, e.id)]?.timestamp;

  entries.sort((a, b) {
    final ta = lastOf(a), tb = lastOf(b);
    if (ta != null && tb != null) return tb.compareTo(ta);
    if (ta != null) return -1;
    if (tb != null) return 1;
    return (a.friend?.displayName ?? '').toLowerCase().compareTo(
      (b.friend?.displayName ?? '').toLowerCase(),
    );
  });
  return entries;
}

/// Conversations: your friends, plus anyone you have exchanged messages with.
/// The search button filters that list by name or username, instantly and
/// without the network; new people are found in Discover.
class ChatListPage extends ConsumerStatefulWidget {
  const ChatListPage({super.key});

  @override
  ConsumerState<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends ConsumerState<ChatListPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _searching = false;

  /// What has been typed, trimmed. The filter is local, so it updates on every
  /// keystroke.
  String _query = '';

  @override
  void dispose() {
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
        _controller.clear();
        _query = '';
        _focus.unfocus();
      }
    });
  }

  void _onChanged(String value) => setState(() => _query = value.trim());

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
    _focus.requestFocus();
  }

  void _openDiscover() {
    if (_searching) _toggleSearch();
    ref.read(navigationNotifierProvider.notifier).setIndex(1);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final view = ref.watch(friendsViewProvider);
    final peersAsync = ref.watch(conversationPeerIdsProvider);

    final friends = view.friends;
    final friendIds = {for (final f in friends) f.id};
    final strangerIds = (peersAsync.value ?? const <String>[])
        .where((id) => !friendIds.contains(id))
        .toList();

    // Only wait on a spinner when there is genuinely nothing to show. A saved
    // copy of the friends list counts as something.
    final nothingToShowYet = !view.hasData && view.isRefreshing;

    Widget body;
    if (currentUser == null || nothingToShowYet) {
      body = Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (_searching && _query.isNotEmpty) {
      // Everyone on the list we can name without asking the server.
      final people = <PublicUser>[
        ...friends,
        for (final id in strangerIds)
          if (ref.watch(knownPersonProvider(id)) case final p?) p,
      ];
      body = _SearchResults(
        query: _query,
        results: filterPeople(people, _query),
        myId: currentUser.id,
        onOpenDiscover: _openDiscover,
      );
    } else if (view.error != null && friends.isEmpty && strangerIds.isEmpty) {
      body = _CenteredMessage(
        text: humanError(view.error, fallback: "Couldn't load your chats."),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(friendsProvider),
      );
    } else if (friends.isEmpty && strangerIds.isEmpty) {
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
            for (final entry in _byRecentActivity(
              friends: friends,
              strangerIds: strangerIds,
              previews: ref.watch(roomPreviewsProvider),
              myId: currentUser.id,
            )) ...[
              entry.friend != null
                  ? _ChatListItem(user: entry.friend!, myId: currentUser.id)
                  : _PeerChatItem(peerId: entry.id, myId: currentUser.id),
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
                  hintText: 'Search your chats',
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

/// The people on your chat list who match, or a way out to Discover.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.results,
    required this.myId,
    required this.onOpenDiscover,
  });

  final String query;
  final List<PublicUser> results;
  final String myId;
  final VoidCallback onOpenDiscover;

  @override
  Widget build(BuildContext context) {
    final discoverLink = Center(
      child: TextButton(
        onPressed: onOpenDiscover,
        child: Text(
          'Looking for someone new? Search Discover',
          style: AppTextStyles.linkText,
        ),
      ),
    );

    if (results.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.search_off, size: 32, color: AppColors.textDim),
          const SizedBox(height: 10),
          Text(
            'No chats match "$query".',
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
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('RESULTS', style: AppTextStyles.eyebrow),
        ),
        for (final user in results) ...[
          _ChatListItem(user: user, myId: myId),
          const SizedBox(height: 10),
        ],
        discoverLink,
      ],
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

/// Someone you have messaged who is not (or is no longer) a friend. Their name
/// and photo come from the copy saved on the phone straight away; the server is
/// asked in the background for anything newer.
class _PeerChatItem extends ConsumerWidget {
  const _PeerChatItem({required this.peerId, required this.myId});

  final String peerId;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known = ref.watch(knownPersonProvider(peerId));
    final fresh = ref.watch(publicUserProvider(peerId));

    final user = fresh.value ?? known;
    if (user != null) return _ChatListItem(user: user, myId: myId);

    // Never seen before and the lookup has not finished (or failed): keep the
    // row so the conversation is never hidden.
    return fresh.when(
      data: (u) => _ChatListItem(user: u, myId: myId),
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
    // The stored summary for this one conversation: no queries, and this row
    // rebuilds only when its own chat changes.
    final preview = ref.watch(roomPreviewProvider(roomId));

    var line = 'Tap to start conversation';
    var time = '';
    if (preview != null) {
      final text = preview.text ?? '';
      final body = preview.isDeleted
          ? 'Message deleted'
          : preview.isImage
          ? (text.isEmpty ? '📷 Photo' : '📷 $text')
          : text;
      line = preview.senderId == myId ? 'You: $body' : body;
      time = formatChatListTime(context, preview.timestamp);
    }

    return ChatRow(
      name: user.displayName,
      preview: line,
      time: time,
      unread: (preview?.unread ?? 0) > 0,
      imageProvider: avatarImage(user.profilePic),
      onTap: () => openChatWith(context, user),
    );
  }
}
