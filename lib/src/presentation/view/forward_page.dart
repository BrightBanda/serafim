import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// How many chats a message can be forwarded to at once.
const forwardMaxTargets = 5;

/// Where a message can be forwarded to.
class _Target {
  const _Target({
    required this.id,
    required this.name,
    required this.subtitle,
    this.person,
    this.group,
  });

  final String id;
  final String name;
  final String subtitle;
  final PublicUser? person;
  final GroupSummary? group;

  bool get isGroup => group != null;

  /// The id the message is sent to: the person's id, or the group's.
  String get recipientId => group?.id ?? id;
}

/// Pick the chats a message is forwarded to.
///
/// One message at a time: choosing several messages to send together is out
/// of scope for now.
class ForwardPage extends ConsumerStatefulWidget {
  /// Forwards a message from a chat.
  const ForwardPage({super.key, required this.messages}) : sharedText = null;

  /// Sends text that another app shared to Serafim (a link, say): the same
  /// picker, a plain message at the end of it.
  const ForwardPage.shareText(String this.sharedText, {super.key})
    : messages = const [];

  final List<LocalMessage> messages;

  /// Set when this is a share from another app rather than a forward.
  final String? sharedText;

  bool get isShare => sharedText != null;

  @override
  ConsumerState<ForwardPage> createState() => _ForwardPageState();
}

class _ForwardPageState extends ConsumerState<ForwardPage> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _chosen = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  LocalMessage get _message => widget.messages.first;

  /// A picture cannot go to a group: the server refuses attachments there.
  /// (Shared text is plain text, which groups take.)
  bool get _groupsBlocked =>
      !widget.isShare && _message.type == MessageType.image;

  bool _matches(String haystack) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return haystack.toLowerCase().contains(q);
  }

  void _toggle(_Target target) {
    if (target.isGroup && _groupsBlocked) return;
    setState(() {
      if (_chosen.contains(target.id)) {
        _chosen.remove(target.id);
      } else if (_chosen.length < forwardMaxTargets) {
        _chosen.add(target.id);
      }
    });
  }

  Future<void> _send(List<_Target> targets) async {
    final chosen = targets.where((t) => _chosen.contains(t.id)).toList();
    if (chosen.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    var sent = 0;
    final failed = <String>[];
    for (final target in chosen) {
      try {
        final vm = ref.read(chatViewModelProvider.notifier);
        final groupId = target.isGroup ? target.group!.id : null;
        final bool ok;
        if (widget.isShare) {
          final me = ref.read(currentAccountIdProvider);
          if (me == null) throw StateError('not signed in');
          await vm.sendMessage(
            roomId: groupId != null
                ? groupRoomId(groupId)
                : ChatViewModel.buildRoomId(me, target.recipientId),
            recipientId: target.recipientId,
            content: widget.sharedText!,
            groupId: groupId,
          );
          ok = true;
        } else {
          ok = await vm.forwardMessage(
            source: _message,
            recipientId: target.recipientId,
            groupId: groupId,
          );
        }
        if (ok) {
          sent++;
        } else {
          failed.add(target.name);
        }
      } catch (e) {
        failed.add('${target.name} (${humanError(e)})');
      }
    }

    if (!mounted) return;
    navigator.pop(sent);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? '${widget.isShare ? 'Sent' : 'Forwarded'} to $sent '
                    '${sent == 1 ? 'chat' : 'chats'}'
              : '${widget.isShare ? 'Sent' : 'Forwarded'} to $sent. '
                    'Could not send to ${failed.join(', ')}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAccountIdProvider);
    final friends = ref.watch(friendsViewProvider).friends;
    final groups = ref.watch(myGroupsProvider).value ?? const <GroupSummary>[];
    final previews = ref.watch(roomPreviewsProvider);
    final peers = ref.watch(conversationPeerIdsProvider);

    final recent = me == null
        ? const <ChatEntry>[]
        : byRecentActivity(
            friends: friends,
            strangerIds: peers
                .where((id) => !friends.any((f) => f.id == id))
                .toList(),
            previews: previews,
            myId: me,
          );

    final targets = <_Target>[
      // Recent chats, most active first.
      for (final entry in recent)
        if (entry.friend != null)
          _Target(
            id: entry.friend!.id,
            name: entry.friend!.displayName,
            subtitle: '@${entry.friend!.username}',
            person: entry.friend,
          ),
      // Everyone you are friends with.
      for (final f in friends)
        if (!recent.any((e) => e.friend?.id == f.id))
          _Target(
            id: f.id,
            name: f.displayName,
            subtitle: '@${f.username}',
            person: f,
          ),
      // Your groups.
      for (final g in groups)
        _Target(
          id: g.id,
          name: g.name,
          subtitle: '${g.memberCount} members',
          group: g,
        ),
    ].where((t) => _matches('${t.name} ${t.subtitle}')).toList();

    final recentCount = recent.length;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: widget.isShare ? 'SEND TO' : 'FORWARD',
        onBack: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  border: Border.all(color: AppColors.lineSoft, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16, color: AppColors.textDim),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        style: AppTextStyles.fieldInput,
                        cursorColor: AppColors.primaryPale,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search chats',
                          hintStyle: AppTextStyles.fieldInput.copyWith(
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isShare)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.paperAlt,
                    border: Border.all(color: AppColors.lineSoft, width: 1.5),
                  ),
                  child: Text(
                    widget.sharedText!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body,
                  ),
                ),
              ),
            if (_groupsBlocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 15,
                      color: AppColors.rustPale,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Pictures can't be sent to groups",
                        style: AppTextStyles.smallDim.copyWith(
                          color: AppColors.rustPale,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: targets.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No chats match that.',
                          style: AppTextStyles.body,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                      children: [
                        if (recentCount > 0)
                          Text('RECENT CHATS', style: AppTextStyles.fieldLabel),
                        for (final t in targets.take(recentCount))
                          _row(t, recent: true),
                        if (targets.length > recentCount) ...[
                          const SizedBox(height: 12),
                          Text('FRIENDS', style: AppTextStyles.fieldLabel),
                          for (final t
                              in targets
                                  .skip(recentCount)
                                  .where((t) => !t.isGroup))
                            _row(t),
                          const SizedBox(height: 12),
                          Text('GROUPS', style: AppTextStyles.fieldLabel),
                          for (final t
                              in targets
                                  .skip(recentCount)
                                  .where((t) => t.isGroup))
                            _row(t),
                        ],
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: SerafimButton(
                  label: _chosen.isEmpty
                      ? 'CHOOSE A CHAT'
                      : 'SEND (${_chosen.length})',
                  onPressed: _chosen.isEmpty ? null : () => _send(targets),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(_Target target, {bool recent = false}) {
    final selected = _chosen.contains(target.id);
    final blocked = target.isGroup && _groupsBlocked;
    final full = !selected && _chosen.length >= forwardMaxTargets;
    return CheckboxListTile(
      value: selected,
      onChanged: blocked || full ? null : (v) => _toggle(target),
      activeColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      secondary: AvatarThumb(
        size: 34,
        isGroup: target.isGroup,
        imageProvider: avatarImage(target.person?.profilePic),
      ),
      title: Text(
        target.name,
        style: AppTextStyles.body.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        blocked ? "Pictures can't be sent to groups" : target.subtitle,
        style: AppTextStyles.smallDim.copyWith(
          color: blocked ? AppColors.rustPale : null,
        ),
      ),
    );
  }
}
