import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
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

    Widget content(PublicUser user) => SingleChildScrollView(
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
                AvatarThumb(
                  size: 80,
                  imageProvider: avatarImage(user.profilePic),
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
                  style: AppTextStyles.body.copyWith(color: AppColors.primary),
                ),
                if (user.followsYou) ...[
                  const SizedBox(height: 4),
                  Text('FOLLOWS YOU', style: AppTextStyles.fieldLabel),
                ],
                if (user.followerCount != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${user.followerCount} followers · ${user.followingCount ?? 0} following',
                    style: AppTextStyles.smallDim,
                  ),
                ],
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
        ],
      ),
    );

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
