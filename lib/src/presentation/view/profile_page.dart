import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:serafim/src/presentation/view/main_screen.dart';
import 'package:serafim/src/presentation/view/widgets/profile_posts.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/edit_profile_page.dart';
import 'package:serafim/src/presentation/view/follow_list_page.dart';
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
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(profileViewModelProvider);
    final pic = profileAsync.value?.profilePic;
    final avatar = pic != null && pic.isNotEmpty
        ? CachedNetworkImageProvider(pic)
        : null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'USER PROFILE',
        onBack: () => Navigator.of(context).pop(),
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
                    _ProfileAvatar(
                      imageProvider: avatar,
                      name: profileAsync.value?.displayName ?? 'You',
                    ),
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
                    _Bio(bio: profileAsync.value?.bio),
                    const SizedBox(height: 10),
                    // The account id from sign-in: the same id the server
                    // knows this account by, and what people search for.
                    if (user != null) UidRow(uid: user.id),
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
              if (user != null) ProfilePosts(userId: user.id),
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
    final view = ref.watch(friendsViewProvider);
    final count = view.hasData ? view.friends.length : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == null ? 'FRIENDS' : 'FRIENDS ($count)',
          style: AppTextStyles.eyebrow,
        ),
        const SizedBox(height: 8),
        if (!view.hasData && view.error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
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
          )
        else if (!view.hasData)
          _FriendsBox(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    humanError(
                      view.error,
                      fallback: "Couldn't load your friends.",
                    ),
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
          )
        else if (view.friends.isEmpty)
          _FriendsBox(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No friends yet. Find people in Discover.',
                    style: AppTextStyles.body,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Profile is a page over the tabs now: close it, then go.
                    Navigator.of(context).pop();
                    ref
                        .read(navigationNotifierProvider.notifier)
                        .setIndex(discoverTabIndex);
                  },
                  child: Text('Discover', style: AppTextStyles.linkText),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (final friend in view.friends.take(5)) ...[
                _FriendRow(friend: friend),
                const SizedBox(height: 8),
              ],
              if (view.friends.length > 5)
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FollowListPage(
                          title: 'FRIENDS',
                          provider: friendsProvider,
                          emptyText: 'No friends yet.',
                        ),
                      ),
                    ),
                    child: Text('See all', style: AppTextStyles.linkText),
                  ),
                ),
            ],
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
            TappableAvatar(
              size: 36,
              heroTag: 'friends:${friend.id}',
              name: friend.displayName,
              image: avatarImage(friend.profilePic),
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
  const _ProfileAvatar({required this.imageProvider, required this.name});

  final ImageProvider? imageProvider;
  final String name;

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
      heroTag: 'me',
      onPhotoTap: () => openProfilePhoto(
        context,
        image: widget.imageProvider,
        heroTag: 'me',
        name: widget.name,
      ),
    );
  }
}

/// The bio under the name, or a nudge to add one.
class _Bio extends StatelessWidget {
  const _Bio({required this.bio});

  final String? bio;

  @override
  Widget build(BuildContext context) {
    final text = bio?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text.isEmpty ? 'No bio yet. Add one with Edit profile.' : text,
        textAlign: TextAlign.center,
        style: text.isEmpty
            ? AppTextStyles.smallDim.copyWith(fontStyle: FontStyle.italic)
            : AppTextStyles.body.copyWith(
                color: AppColors.text,
                fontSize: 12.5,
              ),
      ),
    );
  }
}

/// Shows the account's UID with a copy button. Copies exactly [uid] — the
/// id the server uses — never the name or username.
class UidRow extends StatelessWidget {
  const UidRow({super.key, required this.uid});

  final String uid;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: uid));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('UID copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Copy your UID',
      child: Material(
        color: AppColors.paper,
        shape: Border.all(color: AppColors.lineSoft, width: 1.5),
        child: InkWell(
          onTap: () => _copy(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              children: [
                Text('UID', style: AppTextStyles.fieldLabel),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    uid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.smallDim.copyWith(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: AppColors.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy UID',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context),
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: AppColors.primaryPale,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
