import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/edit_profile_page.dart';
import 'package:serafim/src/presentation/view/follow_list_page.dart';
import 'package:serafim/src/presentation/view/settings/appearance_settings_page.dart';
import 'package:serafim/src/presentation/view/settings/chat_settings_page.dart';
import 'package:serafim/src/presentation/view/settings/notification_settings_page.dart';
import 'package:serafim/src/presentation/view/settings/privacy_settings_page.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/user_card.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/avatar_picker.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/setting_tile.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  static void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(profileViewModelProvider);
    final pic = profileAsync.value?.profilePic;
    final avatar = pic != null && pic.isNotEmpty ? NetworkImage(pic) : null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'USER PROFILE',
        trailing: AvatarThumb(size: 26, imageProvider: avatar),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Main Profile Card ---
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
                    _ProfileAvatar(imageProvider: avatar),
                    const SizedBox(height: 14),
                    // Display Name
                    Text(
                      profileAsync.value?.displayName ?? 'OPERATOR',
                      style: AppTextStyles.displayHeading,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    // Username
                    Text(
                      '@${profileAsync.value?.username ?? 'operator'}',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    // Email
                    Text(
                      user?.email ?? 'no email on file',
                      style: AppTextStyles.smallDim,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    // UID
                    Text(
                      'UID: ${user?.id ?? 'UNKNOWN'}',
                      style: AppTextStyles.smallDim.copyWith(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    const _FollowCounts(),
                    const SizedBox(height: 16),
                    // Edit Profile Button
                    OutlinedButton.icon(
                      onPressed: profileAsync.value == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => EditProfilePage(
                                  profile: profileAsync.value!,
                                ),
                              ),
                            ),
                      icon: Icon(Icons.edit, size: 14, color: AppColors.text),
                      label: Text(
                        'EDIT PROFILE',
                        style: AppTextStyles.buttonLabel.copyWith(
                          fontSize: 11,
                          color: AppColors.text,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.line, width: 1.5),
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // --- Interests ---
              Text('INTERESTS', style: AppTextStyles.eyebrow),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  border: Border.all(color: AppColors.lineSoft, width: 1.5),
                ),
                child: Text(
                  profileAsync.value?.interests.join(', ') ??
                      'No interests set',
                  style: AppTextStyles.body,
                ),
              ),

              const SizedBox(height: 24),

              // --- Friends ---
              const _FriendsSection(),

              const SizedBox(height: 24),

              // --- Preferences & Settings ---
              Text('SETTINGS & PREFERENCES', style: AppTextStyles.eyebrow),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.security,
                title: 'Privacy Settings',
                subtitle: 'Read receipts, who can send you friend requests',
                onTap: () => _open(context, const PrivacySettingsPage()),
              ),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.notifications_none,
                title: 'Notification Settings',
                subtitle: 'Message banners and sounds',
                onTap: () => _open(context, const NotificationSettingsPage()),
              ),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.chat_bubble_outline,
                title: 'Chat Settings',
                subtitle: 'Photo quality, how long messages are kept',
                onTap: () => _open(context, const ChatSettingsPage()),
              ),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.palette_outlined,
                title: 'Theme & Appearance',
                subtitle: 'Text size',
                onTap: () => _open(context, const AppearanceSettingsPage()),
              ),

              const SizedBox(height: 36),

              // --- Logout Action ---
              SerafimButton(
                label: 'Log out',
                //isLoading: auth.isBusy,
                onPressed: () =>
                    ref.read(authViewModelProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsSection extends ConsumerWidget {
  const _FriendsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsProvider);
    final count = friendsAsync.value?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == null ? 'FRIENDS' : 'FRIENDS ($count)',
          style: AppTextStyles.eyebrow,
        ),
        const SizedBox(height: 8),
        friendsAsync.when(
          loading: () => Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          error: (error, _) => _FriendsBox(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    humanError(error, fallback: "Couldn't load your friends."),
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.rustPale,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(friendsProvider),
                  child: Text('Retry', style: AppTextStyles.linkText),
                ),
              ],
            ),
          ),
          data: (friends) {
            if (friends.isEmpty) {
              return _FriendsBox(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'No friends yet. Find people in Discover.',
                        style: AppTextStyles.body,
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(navigationNotifierProvider.notifier)
                          .setIndex(1),
                      child: Text('Discover', style: AppTextStyles.linkText),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final friend in friends) ...[
                  _FriendRow(friend: friend),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FriendsBox extends StatelessWidget {
  const _FriendsBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.lineSoft, width: 1.5),
      ),
      child: child,
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend});

  final PublicUser friend;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfilePage(userId: friend.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Row(
          children: [
            AvatarThumb(
              size: 36,
              imageProvider: avatarImage(friend.profilePic),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '@${friend.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.smallDim,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Message',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: AppColors.primaryPale,
              ),
              onPressed: () => openChatWith(context, friend),
            ),
          ],
        ),
      ),
    );
  }
}

/// Followers / Following counts that open the lists.
class _FollowCounts extends ConsumerWidget {
  const _FollowCounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followers = ref.watch(followersProvider).value?.length;
    final following = ref.watch(followingProvider).value?.length;

    Widget stat(String label, int? count, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Text(
                count?.toString() ?? '–',
                style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
              ),
              Text(label.toUpperCase(), style: AppTextStyles.fieldLabel),
            ],
          ),
        );

    void open(
      String title,
      FutureProvider<List<PublicUser>> provider,
      String empty,
    ) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FollowListPage(
            title: title,
            provider: provider,
            emptyText: empty,
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        stat(
          'Followers',
          followers,
          () => open('FOLLOWERS', followersProvider, 'Nobody follows you yet.'),
        ),
        const SizedBox(width: 36),
        stat(
          'Following',
          following,
          () => open(
            'FOLLOWING',
            followingProvider,
            "You aren't following anyone yet.\nFind people in Discover.",
          ),
        ),
      ],
    );
  }
}

/// The profile picture with its change-photo controls. Shows a spinner from the
/// moment a photo is chosen until it has been shrunk and uploaded.
class _ProfileAvatar extends ConsumerStatefulWidget {
  const _ProfileAvatar({required this.imageProvider});

  final ImageProvider? imageProvider;

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _busy = false;

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.rust),
      );
  }

  Future<void> _change() async {
    if (_busy) return;
    try {
      final bytes = await pickShrunkImage(
        context,
        maxSide: 512,
        quality: 80,
        onPicked: () {
          if (mounted) setState(() => _busy = true);
        },
      );
      if (bytes == null) return; // cancelled
      final error = await ref
          .read(profileViewModelProvider.notifier)
          .uploadAvatar(bytes);
      if (error != null) _tell(error);
    } catch (error) {
      _tell(humanError(error, fallback: "Couldn't update your photo."));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AvatarPicker(
      size: 80,
      imageProvider: widget.imageProvider,
      busy: _busy,
      busyLabel: 'Uploading…',
      onEditTap: _change,
      onUploadTap: _change,
    );
  }
}
