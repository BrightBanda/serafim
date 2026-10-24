import 'package:flutter/material.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/providers/typing_providers.dart';
import 'package:serafim/src/providers/wings_providers.dart';
import 'package:serafim/src/utils/wing_mark.dart';
import 'package:serafim/src/presentation/view/main_screen.dart';
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/chat_filter.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/presentation/view/create_group_page.dart';
import 'package:serafim/src/presentation/view/notifications_page.dart';
import 'package:serafim/src/providers/chat_filter_providers.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/utils/group_nav.dart';
import 'package:serafim/src/presentation/view/official_chat_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/notification_providers.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_row.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/official_badge.dart';
import 'package:serafim/src/utils/serafim_chip.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
import 'package:serafim/src/utils/text_edit_dialog.dart';
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
class ChatEntry {
  const ChatEntry(this.id, this.friend, [this.group]);
  final String id;
  final PublicUser? friend;
  final GroupSummary? group;
}

/// Everyone on the list, most recently active first — like any messaging app.
/// People you have not messaged yet come last, alphabetically.
List<ChatEntry> byRecentActivity({
  required List<PublicUser> friends,
  required List<String> strangerIds,
  required Map<String, RoomPreview> previews,
  required String myId,
  List<GroupSummary> groups = const [],
}) {
  final entries = [
    for (final f in friends) ChatEntry(f.id, f),
    for (final id in strangerIds) ChatEntry(id, null),
    for (final g in groups) ChatEntry(g.id, null, g),
  ];
  DateTime? lastOf(ChatEntry e) => e.group != null
      // A group with no messages yet sorts by when you joined.
      ? previews[e.group!.roomId]?.timestamp ?? e.group!.joinedAt
      : previews[ChatViewModel.buildRoomId(myId, e.id)]?.timestamp;

  entries.sort((a, b) {
    final ta = lastOf(a), tb = lastOf(b);
    if (ta != null && tb != null) return tb.compareTo(ta);
    if (ta != null) return -1;
    if (tb != null) return 1;
    return (a.friend?.displayName ?? a.group?.name ?? '')
        .toLowerCase()
        .compareTo(
          (b.friend?.displayName ?? b.group?.name ?? '').toLowerCase(),
        );
  });
  return entries;
}

/// The room a chat is stored under: the group's own id, or a pair of people.
String roomIdFor(ChatEntry entry, String myId) => entry.group != null
    ? entry.group!.roomId
    : ChatViewModel.buildRoomId(myId, entry.id);

/// Keeps only the chats a filter asks for.
///
/// Pure, so the rule can be tested without a widget: friends, groups,
/// unread, or the room ids of a custom filter.
List<ChatEntry> applyChatFilter(
  List<ChatEntry> entries,
  ChatFilter filter,
  Map<String, RoomPreview> previews,
  String myId, {
  Set<String> wingIds = const {},
}) {
  return [
    for (final entry in entries)
      if (_matchesFilter(entry, filter, previews, myId, wingIds)) entry,
  ];
}

bool _matchesFilter(
  ChatEntry entry,
  ChatFilter filter,
  Map<String, RoomPreview> previews,
  String myId,
  Set<String> wingIds,
) {
  switch (filter.kind) {
    case ChatFilterKind.all:
      return true;
    case ChatFilterKind.wings:
      return entry.friend != null && wingIds.contains(entry.friend!.id);
    case ChatFilterKind.friends:
      return entry.friend != null;
    case ChatFilterKind.groups:
      return entry.group != null;
    case ChatFilterKind.unread:
      final room = roomIdFor(entry, myId);
      return (previews[room]?.unread ?? 0) > 0;
    case ChatFilterKind.custom:
      return filter.roomIds.contains(roomIdFor(entry, myId));
  }
}

/// How many chats have something unread in them.
int countUnread(
  List<ChatEntry> entries,
  Map<String, RoomPreview> previews,
  String myId,
) {
  var n = 0;
  for (final entry in entries) {
    final room = roomIdFor(entry, myId);
    if ((previews[room]?.unread ?? 0) > 0) n++;
  }
  return n;
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
    ref.read(navigationNotifierProvider.notifier).setIndex(discoverTabIndex);
  }

  /// Adds a filter of the person's own: a name and the chats in it.
  Future<void> _addFilter(List<ChatEntry> entries, String myId) async {
    final result = await showModalBottomSheet<_FilterDraft>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      isScrollControlled: true,
      builder: (_) => _FilterSheet(entries: entries, myId: myId),
    );
    if (result == null || !mounted) return;
    final name = result.name.trim();
    if (name.isEmpty) return;
    final filter = ref
        .read(chatFiltersProvider.notifier)
        .add(name, result.roomIds);
    ref.read(selectedChatFilterProvider.notifier).select(filter.id);
  }

  /// Rename, change the chats in, or delete one of the person's filters.
  Future<void> _editFilter(
    ChatFilter filter,
    List<ChatEntry> entries,
    String myId,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetTile(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            _SheetTile(
              icon: Icons.checklist,
              label: 'Edit chats',
              onTap: () => Navigator.pop(sheetContext, 'chats'),
            ),
            _SheetTile(
              icon: Icons.delete_outline,
              label: 'Delete',
              danger: true,
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'delete') {
      ref.read(chatFiltersProvider.notifier).remove(filter.id);
      if (ref.read(selectedChatFilterProvider) == filter.id) {
        ref.read(selectedChatFilterProvider.notifier).select(ChatFilter.all.id);
      }
      return;
    }

    if (action == 'rename') {
      final name = await _askForName(filter.name);
      if (name == null || name.trim().isEmpty || !mounted) return;
      ref.read(chatFiltersProvider.notifier).rename(filter.id, name.trim());
      return;
    }

    // Edit chats.
    final result = await showModalBottomSheet<_FilterDraft>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        entries: entries,
        myId: myId,
        name: filter.name,
        selected: filter.roomIds,
      ),
    );
    if (result == null || !mounted) return;
    ref.read(chatFiltersProvider.notifier).setRooms(filter.id, result.roomIds);
  }

  Future<String?> _askForName(String current) => showTextEditDialog(
    context,
    title: 'Filter name',
    initial: current,
    maxLength: 20,
    titleStyle: AppTextStyles.fieldInput,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    actionStyle: AppTextStyles.linkText,
    validate: (text) => text.trim().isEmpty ? 'Give the filter a name.' : null,
  );

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final view = ref.watch(friendsViewProvider);
    final peerIds = ref.watch(conversationPeerIdsProvider);

    final friends = view.friends;
    final groups = ref.watch(myGroupsProvider).value ?? const <GroupSummary>[];
    final friendIds = {for (final f in friends) f.id};
    final strangerIds = peerIds.where((id) => !friendIds.contains(id)).toList();

    // Which filter is showing, and the chats it lets through.
    final filter = ref.watch(activeChatFilterProvider);
    final previews = ref.watch(roomPreviewsProvider);
    final all = byRecentActivity(
      friends: friends,
      strangerIds: strangerIds,
      groups: groups,
      previews: previews,
      myId: currentUser?.id ?? '',
    );
    final shown = currentUser == null
        ? all
        : applyChatFilter(
            all,
            filter,
            previews,
            currentUser.id,
            wingIds: ref.watch(wingIdsProvider),
          );

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
        showOfficial: officialMatches(_query),
        myId: currentUser.id,
        onOpenDiscover: _openDiscover,
      );
    } else if (view.error != null && friends.isEmpty && strangerIds.isEmpty) {
      body = _CenteredMessage(
        text: humanError(view.error, fallback: "Couldn't load your chats."),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(friendsProvider),
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
                _searching ? 'ALL CHATS' : filter.label.toUpperCase(),
                style: AppTextStyles.eyebrow,
              ),
            ),
            // Every account has the official chat, pinned first. It only
            // belongs under All: it is not a chat with one person.
            if (filter.kind == ChatFilterKind.all) ...[
              const OfficialChatItem(),
              const SizedBox(height: 10),
            ],
            if (friends.isEmpty && strangerIds.isEmpty && groups.isEmpty)
              _CenteredMessage(
                text:
                    'No conversations yet.\nFind people in Discover to start one.',
                actionLabel: 'Open Discover',
                onAction: _openDiscover,
              )
            else if (shown.isEmpty)
              _CenteredMessage(text: _emptyFor(filter)),
            for (final entry in shown) ...[
              entry.group != null
                  ? _GroupChatItem(group: entry.group!, myId: currentUser.id)
                  : entry.friend != null
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NewGroupButton(),
            GestureDetector(
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
            const NotificationBell(),
            const ProfileMenuButton(),
          ],
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
            if (currentUser != null)
              _FilterRow(
                entries: all,
                previews: previews,
                myId: currentUser.id,
                onAdd: () => _addFilter(all, currentUser.id),
                onEdit: (filter) => _editFilter(filter, all, currentUser.id),
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
    this.showOfficial = false,
  });

  final String query;
  final List<PublicUser> results;
  final bool showOfficial;
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

    if (results.isEmpty && !showOfficial) {
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
        if (showOfficial) ...[
          const OfficialChatItem(),
          const SizedBox(height: 10),
        ],
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
  const _CenteredMessage({required this.text, this.actionLabel, this.onAction});

  final String text;

  /// Optional: a filter that shows nothing has nothing to offer to do.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: AppTextStyles.body),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!, style: AppTextStyles.linkText),
              ),
            ],
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
    final typing = ref.watch(typingInRoomProvider(roomId)).isNotEmpty;
    final halo = ref.watch(haloLitProvider(haloKey(user)));

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
      typing: typing,
      halo: halo,
      nameBadge: ref.watch(isWingProvider(user.id)) ? const WingMark() : null,
      time: time,
      unread: (preview?.unread ?? 0) > 0,
      imageProvider: avatarImage(user.profilePic),
      avatarHeroTag: 'chats:${user.id}',
      onTap: () => openChatWith(context, user),
    );
  }
}

/// Whether a chat-list search should include the official chat.
bool officialMatches(String query) {
  final needle = query.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
  if (needle.isEmpty) return false;
  return 'serafim'.contains(needle) || 'official'.contains(needle);
}

/// The official SERAFIM chat's row: the logo, a verified badge, and the latest
/// announcement. Never shows a spinner — the chat list must stay instant.
class OfficialChatItem extends ConsumerWidget {
  const OfficialChatItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(officialChatProvider).value?.latest;
    final unread = ref.watch(officialUnreadProvider);

    return ChatRow(
      name: 'SERAFIM',
      nameBadge: const OfficialBadge(),
      leading: const SerafimMark(size: 38),
      preview: latest?.preview ?? 'Official news and announcements',
      time: latest == null ? '' : formatChatListTime(context, latest.createdAt),
      unread: unread,
      onTap: () => openOfficialChat(context),
    );
  }
}

/// Bell in the top bar with the number of unread notifications.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    final label = unread > 99 ? '99+' : '$unread';

    return Semantics(
      button: true,
      label: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(
                    color: unread > 0 ? AppColors.primary : AppColors.lineSoft,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  unread > 0
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  size: 14,
                  color: unread > 0 ? AppColors.primaryPale : AppColors.textDim,
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.rust,
                      border: Border.all(color: AppColors.line, width: 1.5),
                    ),
                    child: Text(
                      label,
                      style: AppTextStyles.fieldLabel.copyWith(
                        fontSize: 8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group on the chat list: its photo, name and latest message.
class _GroupChatItem extends ConsumerWidget {
  const _GroupChatItem({required this.group, required this.myId});

  final GroupSummary group;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(roomPreviewProvider(group.roomId));
    final typing = ref.watch(typingInRoomProvider(group.roomId)).isNotEmpty;
    var line = '${group.memberCount} members · say hi';
    var time = '';
    if (preview != null) {
      final text = preview.isDeleted ? 'Message deleted' : preview.text ?? '';
      final who = preview.senderId == myId
          ? 'You'
          : ref.watch(knownPersonProvider(preview.senderId))?.displayName;
      line = who == null ? text : '$who: $text';
      time = formatChatListTime(context, preview.timestamp);
    }
    return ChatRow(
      name: group.name,
      isGroup: true,
      preview: line,
      typing: typing,
      time: time,
      unread: (preview?.unread ?? 0) > 0,
      imageProvider: avatarImage(group.photoUrl),
      avatarHeroTag: 'chats-group:${group.id}',
      nameBadge: Icon(
        Icons.groups_rounded,
        size: 14,
        color: AppColors.tealPale,
      ),
      onTap: () => openGroupChat(context, group),
    );
  }
}

/// Top-bar button to start a new group.
class NewGroupButton extends StatelessWidget {
  const NewGroupButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New group',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CreateGroupPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.paper,
              border: Border.all(color: AppColors.lineSoft, width: 1.5),
            ),
            child: Icon(
              Icons.group_add_outlined,
              size: 14,
              color: AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// What the add/edit sheet comes back with.
class _FilterDraft {
  const _FilterDraft(this.name, this.roomIds);
  final String name;
  final Set<String> roomIds;
}

/// The row of filter chips above the chat list: All, Friends, Unread,
/// Groups, then any the person made, then a way to add one.
class _FilterRow extends ConsumerWidget {
  const _FilterRow({
    required this.entries,
    required this.previews,
    required this.myId,
    required this.onAdd,
    required this.onEdit,
  });

  final List<ChatEntry> entries;
  final Map<String, RoomPreview> previews;
  final String myId;
  final VoidCallback onAdd;
  final ValueChanged<ChatFilter> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChatFilterProvider);
    final custom = ref.watch(chatFiltersProvider);
    final unread = countUnread(entries, previews, myId);

    Widget chip(
      ChatFilter filter, {
      String? label,
      VoidCallback? onLongPress,
    }) => GestureDetector(
      onLongPress: onLongPress,
      child: SerafimChip(
        label: label ?? filter.label,
        selected: selected == filter.id,
        onTap: () =>
            ref.read(selectedChatFilterProvider.notifier).select(filter.id),
      ),
    );

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        children: [
          chip(ChatFilter.all),
          const SizedBox(width: 6),
          chip(ChatFilter.friends),
          const SizedBox(width: 6),
          chip(
            ChatFilter.unread,
            label: unread > 0 ? 'Unread $unread' : 'Unread',
          ),
          const SizedBox(width: 6),
          chip(ChatFilter.groups),
          for (final filter in custom) ...[
            const SizedBox(width: 6),
            chip(filter, onLongPress: () => onEdit(filter)),
          ],
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.lineSoft, width: 1.5),
              ),
              child: Text(
                '+ Add filter',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the add/edit sheet: a chat you can put in the filter.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.entries,
    required this.myId,
    this.name = '',
    this.selected = const {},
  });

  final List<ChatEntry> entries;
  final String myId;
  final String name;
  final Set<String> selected;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final Set<String> _rooms = {...widget.selected};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: TextField(
                controller: _name,
                maxLength: 20,
                style: AppTextStyles.fieldInput,
                cursorColor: AppColors.primaryPale,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter name',
                  hintStyle: AppTextStyles.fieldInput.copyWith(
                    color: AppColors.textDim,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  counterStyle: AppTextStyles.smallDim,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final entry in widget.entries)
                    _FilterChatRow(
                      entry: entry,
                      roomId: roomIdFor(entry, widget.myId),
                      selected: _rooms.contains(roomIdFor(entry, widget.myId)),
                      onChanged: (on) {
                        final room = roomIdFor(entry, widget.myId);
                        setState(() {
                          if (on) {
                            _rooms.add(room);
                          } else {
                            _rooms.remove(room);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: SerafimButton(
                label: 'SAVE',
                onPressed: () => Navigator.pop(
                  context,
                  _FilterDraft(_name.text.trim(), _rooms),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChatRow extends StatelessWidget {
  const _FilterChatRow({
    required this.entry,
    required this.roomId,
    required this.selected,
    required this.onChanged,
  });

  final ChatEntry entry;
  final String roomId;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final name = entry.friend?.displayName ?? entry.group?.name ?? entry.id;
    return GestureDetector(
      onTap: () => onChanged(!selected),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppColors.line : AppColors.lineSoft,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: AppTextStyles.fieldInput,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the "edit filter" sheet.
class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.rustPale : AppColors.text;
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: AppTextStyles.body.copyWith(color: color)),
      onTap: onTap,
    );
  }
}

/// What to say when a filter shows nothing.
String _emptyFor(ChatFilter filter) => switch (filter.kind) {
  ChatFilterKind.all => 'No conversations yet.',
  ChatFilterKind.friends => 'No chats with friends yet.',
  ChatFilterKind.unread => 'No unread chats.',
  ChatFilterKind.groups => 'No group chats yet.',
  ChatFilterKind.custom => 'No chats in this filter.',
  ChatFilterKind.wings =>
    'No Wings yet. Name up to six closest friends in your profile.',
};
