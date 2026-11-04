import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Picks friends to invite into a Circle. The Owner and Overseers can also
/// add them straight away; the server only does that for friends whose
/// privacy allows being added, and invites the others instead.
class CircleInvitePage extends ConsumerStatefulWidget {
  const CircleInvitePage({super.key, required this.circleId});

  final String circleId;

  @override
  ConsumerState<CircleInvitePage> createState() => _CircleInvitePageState();
}

class _CircleInvitePageState extends ConsumerState<CircleInvitePage> {
  final _picked = <String>{};
  bool _add = false;
  bool _busy = false;

  Future<void> _send(CircleDetail circle, List<PublicUser> friends) async {
    if (_picked.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final results = await ref
          .read(circleInviteProvider)
          .invite(circle.id, _picked.toList(), add: _add);
      if (!mounted) return;
      setState(_picked.clear);
      final names = {for (final f in friends) f.id: f.displayName};
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          backgroundColor: AppColors.paperAlt,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(
            'Done',
            style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${names[r.userId] ?? 'Someone'}: ${describeInvite(r)}',
                    style: AppTextStyles.body,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text('OK', style: AppTextStyles.linkText),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(circleDetailProvider(widget.circleId));
    final friends = ref.watch(friendsProvider);
    final circle = detail.value;
    final manager = circle?.myRole?.canManage == true;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: manager ? 'ADD PEOPLE' : 'INVITE FRIENDS',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: circle == null || !friends.hasValue
            ? Center(
                child: detail.hasError || friends.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          humanError(detail.error ?? friends.error!),
                          style: AppTextStyles.body,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : CircularProgressIndicator(color: AppColors.primary),
              )
            : _body(circle, friends.value!, manager),
      ),
    );
  }

  Widget _body(CircleDetail circle, List<PublicUser> friends, bool manager) {
    final inCircle = {for (final m in circle.members) m.user.id};
    final candidates = [
      for (final f in friends)
        if (!inCircle.contains(f.id)) f,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
      children: [
        Text(
          'Only friends can be invited. They get a notification and choose '
          'whether to join.',
          style: AppTextStyles.smallDim,
        ),
        if (manager) ...[
          const SizedBox(height: 12),
          SettingsSwitchRow(
            key: const ValueKey('circle-invite-add'),
            title: 'Add them straight away',
            subtitle:
                'For friends who allow being added. Anyone else gets an '
                'invitation.',
            value: _add,
            onChanged: (on) => setState(() => _add = on),
          ),
        ],
        const SizedBox(height: 12),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              friends.isEmpty
                  ? 'Add friends first, then invite them here.'
                  : 'All your friends are already in this Circle.',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
          ),
        for (final friend in candidates)
          _FriendRow(
            friend: friend,
            invited: circle.invitedUserIds.contains(friend.id),
            picked: _picked.contains(friend.id),
            onTap: () => setState(() {
              if (!_picked.remove(friend.id)) _picked.add(friend.id);
            }),
          ),
        const SizedBox(height: 16),
        SerafimButton(
          key: const ValueKey('circle-invite-send'),
          label: _busy
              ? 'SENDING…'
              : _picked.isEmpty
              ? 'PICK FRIENDS'
              : '${_add ? 'ADD' : 'INVITE'} ${_picked.length}',
          onPressed: _picked.isEmpty || _busy
              ? null
              : () => _send(circle, friends),
        ),
      ],
    );
  }
}

/// What happened to one person, in words.
String describeInvite(CircleInviteResult r) => switch (r.status) {
  CircleInviteStatus.added => 'added to the Circle.',
  CircleInviteStatus.invited => r.message ?? 'invited.',
  CircleInviteStatus.alreadyInvited =>
    r.message ?? 'already has an invitation.',
  CircleInviteStatus.alreadyMember => 'already in the Circle.',
  CircleInviteStatus.notFriends => r.message ?? 'not your friend.',
  CircleInviteStatus.banned => r.message ?? 'banned from this Circle.',
  CircleInviteStatus.unavailable => r.message ?? "isn't available.",
};

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.invited,
    required this.picked,
    required this.onTap,
  });

  final PublicUser friend;
  final bool invited;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pic = friend.profilePic;
    return GestureDetector(
      key: ValueKey('circle-invite-${friend.id}'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: picked ? AppColors.paperRaised : AppColors.paperAlt,
          border: Border.all(
            color: picked ? AppColors.primary : AppColors.lineSoft,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AvatarThumb(
              size: 34,
              imageProvider: pic != null && pic.isNotEmpty
                  ? CachedNetworkImageProvider(pic)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayName,
                    style: AppTextStyles.fieldInput.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    invited ? 'Invited' : '@${friend.username}',
                    style: AppTextStyles.smallDim,
                  ),
                ],
              ),
            ),
            Icon(
              picked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: picked ? AppColors.primaryPale : AppColors.textDim,
            ),
          ],
        ),
      ),
    );
  }
}
