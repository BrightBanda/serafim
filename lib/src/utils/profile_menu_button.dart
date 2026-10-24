import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/profile_page.dart';
import 'package:serafim/src/presentation/view/settings_page.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/halo_sheet.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Your photo in the top bar of every main tab. It opens a short menu:
/// your profile and settings, and log out.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pic = ref.watch(profileViewModelProvider).value?.profilePic;
    final haloLit = ref.watch(myHaloLitProvider);
    final avatar = pic != null && pic.isNotEmpty
        ? CachedNetworkImageProvider(pic)
        : null;
    return PopupMenuButton<String>(
      tooltip: 'Profile',
      padding: EdgeInsets.zero,
      color: AppColors.paperAlt,
      onSelected: (value) {
        if (value == 'halo') {
          showHaloSheet(context, ref);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                value == 'profile' ? const ProfilePage() : const SettingsPage(),
          ),
        );
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'profile',
          child: Text('Profile', style: AppTextStyles.body),
        ),
        PopupMenuItem(
          value: 'halo',
          child: Text(haloLit ? 'Halo: on' : 'Halo', style: AppTextStyles.body),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Text('Settings', style: AppTextStyles.body),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AvatarThumb(size: 26, imageProvider: avatar, halo: haloLit),
      ),
    );
  }
}
