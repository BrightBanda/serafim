import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/small_action_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Opens (or starts) the conversation with [user].
void openChatWith(BuildContext context, PublicUser user) {
  openChatWithNavigator(Navigator.of(context), user);
}

/// Same, from code that has a navigator but no BuildContext (the banner).
void openChatWithNavigator(NavigatorState navigator, PublicUser user) {
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ChatThreadPage(
        contactName: user.displayName,
        username: user.username,
        profilePic: user.profilePic,
        recipientId: user.id,
      ),
    ),
  );
}

ImageProvider? avatarImage(String? url) =>
    url != null && url.isNotEmpty ? CachedNetworkImageProvider(url) : null;

/// A person in Discover / search results / requests: who they are, why they
/// are shown (only when real shared interests exist), and what you can do.
class UserCard extends StatelessWidget {
  const UserCard({super.key, required this.user});

  final PublicUser user;

  @override
  Widget build(BuildContext context) {
    final reason = discoverReason(user.sharedInterests);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfilePage(userId: user.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.line,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarThumb(
                  size: 44,
                  imageProvider: avatarImage(user.profilePic),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '@${user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.smallDim,
                      ),
                      if (reason != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.tealPale,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FriendActionRow(user: user),
          ],
        ),
      ),
    );
  }
}

/// Message + the friend action that fits [user]'s current status.
class FriendActionRow extends ConsumerStatefulWidget {
  const FriendActionRow({
    super.key,
    required this.user,
    this.showUnfriend = false,
    this.showMessage = true,
  });

  final PublicUser user;

  /// Profile pages offer unfriending; list cards stay uncluttered.
  final bool showUnfriend;

  /// Hidden when you got here from the conversation itself.
  final bool showMessage;

  @override
  ConsumerState<FriendActionRow> createState() => _FriendActionRowState();
}

class _FriendActionRowState extends ConsumerState<FriendActionRow> {
  String? _busyAction;

  Future<void> _run(
    String name,
    Future<String?> Function(SocialActions) fn,
  ) async {
    if (_busyAction != null) return; // No double taps / duplicate requests.
    setState(() => _busyAction = name);
    final error = await fn(ref.read(socialActionsProvider));
    if (!mounted) return;
    setState(() => _busyAction = null);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.rust),
        );
    }
  }

  Future<void> _confirmUnfriend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Remove friend?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          'You and ${widget.user.displayName} will no longer be able to send '
          'each other attachments. Your messages stay.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _run('unfriend', (a) => a.unfriend(widget.user.id));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final busy = _busyAction;

    final buttons = <Widget>[
      if (widget.showMessage)
        SmallActionButton(
          label: 'Message',
          icon: Icons.chat_bubble_outline,
          onPressed: () => openChatWith(context, user),
        ),
      ...switch (user.friendStatus) {
        FriendStatus.none => [
          if (user.acceptsFriendRequests)
            SmallActionButton(
              label: 'Add friend',
              icon: Icons.person_add_alt,
              primary: true,
              busy: busy == 'add',
              onPressed: () => _run('add', (a) => a.sendRequest(user.id)),
            )
          else
            const SmallActionButton(
              label: 'Requests off',
              icon: Icons.block,
              onPressed: null,
            ),
        ],
        FriendStatus.requestSent => [
          const SmallActionButton(
            label: 'Request sent',
            icon: Icons.check,
            onPressed: null,
          ),
          SmallActionButton(
            label: 'Cancel',
            busy: busy == 'cancel',
            onPressed: () => _run('cancel', (a) => a.cancel(user.id)),
          ),
        ],
        FriendStatus.requestReceived => [
          SmallActionButton(
            label: 'Accept',
            icon: Icons.check,
            primary: true,
            busy: busy == 'accept',
            onPressed: () => _run('accept', (a) => a.accept(user.id)),
          ),
          SmallActionButton(
            label: 'Decline',
            busy: busy == 'reject',
            onPressed: () => _run('reject', (a) => a.reject(user.id)),
          ),
        ],
        FriendStatus.friends => [
          const SmallActionButton(
            label: 'Friends',
            icon: Icons.people_alt_outlined,
            onPressed: null,
          ),
          if (widget.showUnfriend)
            SmallActionButton(
              label: 'Unfriend',
              busy: busy == 'unfriend',
              onPressed: _confirmUnfriend,
            ),
        ],
      },
    ];

    // Following is separate from friendship and works in every state.
    buttons.add(
      user.isFollowing
          ? SmallActionButton(
              label: 'Following',
              icon: Icons.check,
              busy: busy == 'unfollow',
              onPressed: () => _run('unfollow', (a) => a.unfollow(user.id)),
            )
          : SmallActionButton(
              label: 'Follow',
              icon: Icons.add,
              busy: busy == 'follow',
              onPressed: () => _run('follow', (a) => a.follow(user.id)),
            ),
    );

    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}
