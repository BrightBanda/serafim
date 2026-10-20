import 'package:flutter/material.dart';
import 'package:serafim/src/presentation/view/widgets/profile_posts.dart';
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/follow_list_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/relation_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_chip.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// Another person's public profile with the actions that fit your
/// relationship to them. Loaded by id so it is always current, whether you
/// arrived from Discover, search, the friends list or a chat.
class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({
    super.key,
    required this.userId,
    this.fromChat = false,
  });

  final String userId;

  /// Opened from that person's own conversation, so there is no point offering
  /// a Message button that would just open the same chat again.
  final bool fromChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(publicUserProvider(userId));
    // Straight from the copy saved on the phone, so opening a profile is
    // instant; the server's answer replaces it a moment later.
    final saved = ref.watch(knownPersonProvider(userId));
    final shown = userAsync.value ?? saved;
    final isMe = ref.watch(currentAccountIdProvider) == userId;

    Widget content(PublicUser server) {
      // Counts follow a Follow/Unfollow tap at once.
      final user = watchWithPending(ref, server);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                border: Border.all(color: AppColors.line, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.line,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                children: [
                  TappableAvatar(
                    size: 80,
                    heroTag: 'profile:${user.id}',
                    name: user.displayName,
                    image: avatarImage(user.profilePic),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    user.displayName,
                    style: AppTextStyles.displayHeading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  if (user.followsYou) ...[
                    const SizedBox(height: 4),
                    Text('FOLLOWS YOU', style: AppTextStyles.fieldLabel),
                  ],
                  if ((user.bio ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      user.bio!.trim(),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.text,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _Connections(user: user, isMe: isMe),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.center,
                    child: FriendActionRow(
                      user: user,
                      showUnfriend: true,
                      showMessage: !fromChat,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('INTERESTS', style: AppTextStyles.eyebrow),
            const SizedBox(height: 8),
            if (user.interests.isEmpty)
              Text('No interests listed.', style: AppTextStyles.body)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final interest in user.interests)
                    SerafimChip(
                      label: interest,
                      selected: user.sharedInterests
                          .map((e) => e.toLowerCase())
                          .contains(interest.toLowerCase()),
                    ),
                ],
              ),
            if (user.sharedInterests.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Highlighted: interests you share.',
                style: AppTextStyles.smallDim,
              ),
            ],
            ProfilePosts(
              userId: userId,
              // The server leaves the counts out exactly when the profile is
              // locked and you are neither the owner nor a friend.
              locked: user.profileLocked && !isMe && user.friendCount == null,
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'PROFILE',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: shown != null
            ? content(shown)
            : userAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          humanError(error),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.rustPale,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(publicUserProvider(userId)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: content,
              ),
      ),
    );
  }
}

/// Friends · followers · following, each opening the list — or a note that
/// the person keeps them private.
class _Connections extends StatelessWidget {
  const _Connections({required this.user, required this.isMe});

  final PublicUser user;
  final bool isMe;

  void _open(
    BuildContext context,
    String title,
    FutureProvider<List<PublicUser>> provider,
    String empty,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FollowListPage(title: title, provider: provider, emptyText: empty),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The server leaves the counts out exactly when you may not see the lists
    // (locked, and you are neither the owner nor a friend).
    if (user.profileLocked && !isMe && user.friendCount == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.paper,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 16, color: AppColors.textDim),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This profile is locked',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Only friends can see their friends and followers.',
                    style: AppTextStyles.smallDim,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final name = user.displayName;
    Widget stat(String label, int? count, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          children: [
            Text(
              count?.toString() ?? '–',
              style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
            ),
            Text(label.toUpperCase(), style: AppTextStyles.fieldLabel),
          ],
        ),
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        stat(
          'Friends',
          user.friendCount,
          () => _open(
            context,
            'FRIENDS',
            friendsOfProvider(user.id),
            '$name has no friends on Serafim yet.',
          ),
        ),
        stat(
          'Followers',
          user.followerCount,
          () => _open(
            context,
            'FOLLOWERS',
            followersOfProvider(user.id),
            'Nobody follows $name yet.',
          ),
        ),
        stat(
          'Following',
          user.followingCount,
          () => _open(
            context,
            'FOLLOWING',
            followingOfProvider(user.id),
            "$name isn't following anyone yet.",
          ),
        ),
      ],
    );
  }
}
