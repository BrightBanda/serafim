import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/presentation/view/composer_page.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/presentation/view/widgets/load_more_button.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// One Circle: its posts, what it is about, and who is in it.
class CircleDetailPage extends ConsumerStatefulWidget {
  const CircleDetailPage({super.key, required this.circleId});

  final String circleId;

  @override
  ConsumerState<CircleDetailPage> createState() => _CircleDetailPageState();
}

class _CircleDetailPageState extends ConsumerState<CircleDetailPage> {
  int _tab = 0;

  Future<void> _compose() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComposerPage(circleId: widget.circleId),
      ),
    );
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(circleDetailProvider(widget.circleId));

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(title: 'CIRCLE', onBack: _goBack),
      body: detail.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              humanError(e),
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (circle) => Column(
          children: [
            _Header(circle: circle),
            _Tabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
            Expanded(
              child: switch (_tab) {
                0 => _PostsTab(circle: circle),
                1 => _AboutTab(circle: circle),
                _ => _MembersTab(circle: circle),
              },
            ),
          ],
        ),
      ),
      floatingActionButton: detail.hasValue && detail.value!.isMember
          ? FloatingActionButton.extended(
              onPressed: _compose,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text('POST', style: AppTextStyles.buttonLabel),
            )
          : null,
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = circle.myRole;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  circle.name,
                  style: AppTextStyles.displayHeading.copyWith(fontSize: 22),
                ),
              ),
              if (role != null)
                Text(
                  role.label.toUpperCase(),
                  style: AppTextStyles.eyebrow.copyWith(fontSize: 9),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${circle.summary.memberCount} members',
                style: AppTextStyles.smallDim,
              ),
              if (circle.summary.category != null) ...[
                Text(' · ', style: AppTextStyles.smallDim),
                Text(circle.summary.category!, style: AppTextStyles.smallDim),
              ],
              Text(' · ', style: AppTextStyles.smallDim),
              Text(
                circle.summary.visibility.label,
                style: AppTextStyles.smallDim,
              ),
            ],
          ),
          if (circle.summary.myRequestPending) ...[
            const SizedBox(height: 8),
            Text(
              'Your request to join is waiting for an Overseer.',
              style: AppTextStyles.smallDim.copyWith(
                color: AppColors.primaryPale,
              ),
            ),
          ],
          if (circle.summary.iAmBanned) ...[
            const SizedBox(height: 8),
            Text(
              'You have been banned from this Circle.',
              style: AppTextStyles.smallDim.copyWith(color: AppColors.rustPale),
            ),
          ],
          if (!circle.isMember && !circle.summary.iAmBanned) ...[
            const SizedBox(height: 12),
            _JoinButton(circle: circle),
          ],
        ],
      ),
    );
  }
}

class _JoinButton extends ConsumerStatefulWidget {
  const _JoinButton({required this.circle});

  final CircleDetail circle;

  @override
  ConsumerState<_JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends ConsumerState<_JoinButton> {
  bool _busy = false;

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      await ref.read(circleJoinProvider.notifier).join(widget.circle.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final circle = widget.circle;
    if (circle.summary.visibility == CircleVisibility.inviteOnly) {
      return Text('This Circle is invite-only.', style: AppTextStyles.smallDim);
    }
    return GestureDetector(
      onTap: _busy ? null : _join,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary,
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Text(circle.summary.joinLabel, style: AppTextStyles.buttonLabel),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Posts', 'About', 'Members'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: index == i
                      ? AppColors.paperRaised
                      : Colors.transparent,
                  border: Border.all(
                    color: index == i ? AppColors.primary : AppColors.lineSoft,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  labels[i].toUpperCase(),
                  style: AppTextStyles.fieldLabel.copyWith(
                    color: index == i
                        ? AppColors.primaryPale
                        : AppColors.textDim,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _PostsTab extends ConsumerWidget {
  const _PostsTab({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(circlePostsProvider(circle.id));

    return posts.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            humanError(e),
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                circle.isMember
                    ? 'No posts yet. Start the conversation.'
                    : 'Join this Circle to see its posts.',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
          children: [
            for (final post in page.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PostCard(
                  post: post,
                  onSpark: (on) =>
                      ref.read(sparkProvider.notifier).togglePost(post, on: on),
                  onComment: () =>
                      openPost(context, post.id, focusComment: true),
                  canManage: circle.myRole?.canManage == true,
                  footer: circle.myRole?.canManage == true
                      ? _OverseerActions(post: post, circle: circle)
                      : null,
                ),
              ),
            if (page.hasMore)
              LoadMoreButton(
                onLoad: ref
                    .read(circlePostsProvider(circle.id).notifier)
                    .loadMore,
              ),
          ],
        );
      },
    );
  }
}

/// Pin and remove, for a Circle's Overseers.
class _OverseerActions extends ConsumerWidget {
  const _OverseerActions({required this.post, required this.circle});

  final Post post;
  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the pin lives here. Removing a post goes through the same
    // overflow menu every post has, so there is one delete flow.
    return GestureDetector(
      onTap: () => ref
          .read(pinProvider.notifier)
          .toggle(post.id, on: !post.pinned, circleId: circle.id),
      child: Icon(
        post.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        size: 15,
        color: post.pinned ? AppColors.primaryPale : AppColors.textDim,
      ),
    );
  }
}

class _AboutTab extends ConsumerWidget {
  const _AboutTab({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = circle.myRole;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        if (circle.summary.description != null &&
            circle.summary.description!.isNotEmpty) ...[
          Text(circle.summary.description!, style: AppTextStyles.fieldInput),
          const SizedBox(height: 20),
        ],
        _Row(label: 'Category', value: circle.summary.category ?? '—'),
        _Row(label: 'Visibility', value: circle.summary.visibility.label),
        _Row(label: 'Members', value: '${circle.summary.memberCount}'),
        _Row(label: 'Created', value: _date(circle.summary.createdAt)),
        _Row(
          label: 'Posting',
          value: circle.postingEnabled ? 'Open' : 'Read only',
        ),
        if (circle.rules != null && circle.rules!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('RULES', style: AppTextStyles.eyebrow.copyWith(fontSize: 9)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.paperAlt,
              border: Border.all(color: AppColors.lineSoft, width: 1.5),
            ),
            child: Text(circle.rules!, style: AppTextStyles.fieldInput),
          ),
        ],
        if (circle.isMember) ...[
          const SizedBox(height: 24),
          Text(
            'NOTIFICATIONS',
            style: AppTextStyles.eyebrow.copyWith(fontSize: 9),
          ),
          const SizedBox(height: 8),
          _NotificationSettings(circle: circle),
        ],
        if (role?.canManage == true && circle.pendingRequests.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('MANAGE', style: AppTextStyles.eyebrow.copyWith(fontSize: 9)),
          const SizedBox(height: 8),
          _RequestList(circle: circle),
        ],
        if (circle.isMember) ...[
          const SizedBox(height: 24),
          _LeaveRow(circle: circle),
        ],
        if (role?.isOwner == true) ...[
          const SizedBox(height: 12),
          _DangerRow(circle: circle),
        ],
      ],
    );
  }

  static String _date(DateTime when) =>
      '${when.day}/${when.month}/${when.year}';
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: AppTextStyles.fieldLabel),
          ),
          Expanded(child: Text(value, style: AppTextStyles.fieldInput)),
        ],
      ),
    );
  }
}

/// Your notification switches for this Circle: mute it entirely, or choose
/// what it tells you about. A switch moves at once; if the server refuses,
/// it moves back and says why.
class _NotificationSettings extends ConsumerStatefulWidget {
  const _NotificationSettings({required this.circle});

  final CircleDetail circle;

  @override
  ConsumerState<_NotificationSettings> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  late CircleNotificationSettings _shown = _fromServer;

  CircleNotificationSettings get _fromServer =>
      widget.circle.summary.myNotifications ??
      const CircleNotificationSettings();

  @override
  void didUpdateWidget(covariant _NotificationSettings old) {
    super.didUpdateWidget(old);
    // The server's answer (after a save, or a refresh) is the truth.
    _shown = _fromServer;
  }

  Future<void> _change(
    CircleNotificationSettings next, {
    bool? muted,
    bool? posts,
    bool? replies,
    bool? mentions,
  }) async {
    final before = _shown;
    setState(() => _shown = next);
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(circleSettingsProvider.notifier)
        .change(
          widget.circle.id,
          muted: muted,
          posts: posts,
          replies: replies,
          mentions: mentions,
        );
    if (error == null) return;
    if (mounted) setState(() => _shown = before);
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _shown;
    // Muted means nothing at all, so the finer switches rest while it is.
    ValueChanged<bool>? unlessMuted(ValueChanged<bool> change) =>
        s.muted ? null : change;
    return Column(
      children: [
        SettingsSwitchRow(
          key: const ValueKey('circle-mute'),
          title: 'Mute this circle',
          subtitle: 'No notifications from it at all',
          value: s.muted,
          onChanged: (on) => _change(s.copyWith(muted: on), muted: on),
        ),
        SettingsSwitchRow(
          key: const ValueKey('circle-notify-posts'),
          title: 'New posts',
          subtitle: 'New posts, and comments on your posts',
          value: s.posts,
          onChanged: unlessMuted(
            (on) => _change(s.copyWith(posts: on), posts: on),
          ),
        ),
        SettingsSwitchRow(
          key: const ValueKey('circle-notify-replies'),
          title: 'Replies',
          subtitle: 'Replies to your comments',
          value: s.replies,
          onChanged: unlessMuted(
            (on) => _change(s.copyWith(replies: on), replies: on),
          ),
        ),
        SettingsSwitchRow(
          key: const ValueKey('circle-notify-mentions'),
          title: 'Mentions',
          subtitle: 'When someone mentions you',
          value: s.mentions,
          onChanged: unlessMuted(
            (on) => _change(s.copyWith(mentions: on), mentions: on),
          ),
        ),
      ],
    );
  }
}

/// Leaving the Circle. The warning says what will actually happen: your
/// posts stay; an owner hands it on (to whom is named); the last member
/// takes it with them.
class _LeaveRow extends ConsumerWidget {
  const _LeaveRow({required this.circle});

  final CircleDetail circle;

  String _warning(String? me) {
    final private = circle.summary.visibility != CircleVisibility.public;
    final rejoin = private
        ? ' To come back you will need to be approved again.'
        : '';
    if (circle.myRole?.isOwner != true) {
      return 'You will stop seeing its posts. Your own posts stay in it.'
          '$rejoin';
    }
    final heir = me == null ? null : circleSuccessor(circle.members, me);
    if (heir == null) {
      return "You're the only member, so the circle and every post in it "
          'will be deleted. Nobody can undo this.';
    }
    return "You're the owner. ${heir.user.displayName} "
        '(${heir.role.label.toLowerCase()}) becomes the owner. Your own '
        'posts stay in it.$rejoin';
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentAccountIdProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'Leave ${circle.name}?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
        ),
        content: Text(_warning(me), style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text('Stay', style: AppTextStyles.linkText),
          ),
          TextButton(
            key: const ValueKey('circle-leave-confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text('Leave', style: AppTextStyles.linkText),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await ref
          .read(circleLeaveProvider.notifier)
          .leave(circle.id);
      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result?.circleDeleted == true
                ? '${circle.name} was deleted.'
                : 'You left ${circle.name}.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      key: const ValueKey('circle-leave'),
      onTap: () => _leave(context, ref),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.logout, size: 16, color: AppColors.rustPale),
            const SizedBox(width: 10),
            Text(
              'Leave this circle',
              style: AppTextStyles.fieldInput.copyWith(
                color: AppColors.rustPale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The people waiting to join.
class _RequestList extends ConsumerWidget {
  const _RequestList({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final request in circle.pendingRequests)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.paperAlt,
              border: Border.all(color: AppColors.lineSoft, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.user.displayName,
                        style: AppTextStyles.fieldInput.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (request.message != null &&
                          request.message!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(request.message!, style: AppTextStyles.smallDim),
                      ],
                    ],
                  ),
                ),
                _SmallButton(
                  label: 'Approve',
                  onTap: () => ref
                      .read(circleRequestProvider.notifier)
                      .approve(circle.id, request.id),
                ),
                const SizedBox(width: 6),
                _SmallButton(
                  label: 'Decline',
                  onTap: () => ref
                      .read(circleRequestProvider.notifier)
                      .reject(circle.id, request.id),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Text(label, style: AppTextStyles.fieldLabel),
      ),
    );
  }
}

/// Deleting a Circle, for its Owner. The name has to be typed back.
class _DangerRow extends ConsumerWidget {
  const _DangerRow({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await _confirm(context, circle.name);
        if (confirmed != true || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        try {
          await ref
              .read(circleServiceProvider)
              .delete(circle.id, confirmName: circle.name);
          navigator.pop();
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.rust, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 16, color: AppColors.rustPale),
            const SizedBox(width: 10),
            Text(
              'Delete this circle',
              style: AppTextStyles.fieldInput.copyWith(
                color: AppColors.rustPale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the Circle's name before deleting it, so a stray tap cannot
/// destroy a community.
Future<bool?> _confirm(BuildContext context, String name) {
  final controller = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        'Delete this circle?',
        style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Every post in it goes too, and nobody can undo it. '
            'Type the name to confirm.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            style: AppTextStyles.fieldInput,
            cursorColor: AppColors.primaryPale,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
              hintText: name,
              hintStyle: AppTextStyles.fieldInput.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel', style: AppTextStyles.linkText),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            controller.text.trim().toLowerCase() == name.trim().toLowerCase(),
          ),
          child: Text('Delete', style: AppTextStyles.linkText),
        ),
      ],
    ),
  );
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRole = circle.myRole;
    if (circle.members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Only members can see who is in this Circle.',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: circle.members.length,
      itemBuilder: (context, index) {
        final member = circle.members[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(color: AppColors.lineSoft, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.user.displayName,
                      style: AppTextStyles.fieldInput.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${member.user.username}',
                      style: AppTextStyles.smallDim,
                    ),
                  ],
                ),
              ),
              Text(
                member.role.label.toUpperCase(),
                style: AppTextStyles.eyebrow.copyWith(fontSize: 8.5),
              ),
              if (myRole?.canRemove(member.role) == true) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => ref
                      .read(circleMemberProvider.notifier)
                      .remove(circle.id, member.user.id),
                  child: Icon(
                    Icons.remove_circle_outline,
                    size: 16,
                    color: AppColors.rustPale,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
