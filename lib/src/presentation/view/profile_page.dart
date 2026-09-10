import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/setting_tile.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final auth = ref.watch(authViewModelProvider);
    final profileAsync = ref.watch(profileViewModelProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const AppTopBar(
        title: 'USER PROFILE',
        trailing: AvatarThumb(size: 26),
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
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.line,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const AvatarThumb(size: 80),
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
                      '@${profileAsync.value?.displayName?.toLowerCase().replaceAll(' ', '') ?? 'operator'}',
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
                    const SizedBox(height: 16),
                    // Edit Profile Button
                    OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Navigate to Edit Profile screen
                      },
                      icon: const Icon(
                        Icons.edit,
                        size: 14,
                        color: AppColors.text,
                      ),
                      label: Text(
                        'EDIT PROFILE',
                        style: AppTextStyles.buttonLabel.copyWith(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AppColors.line,
                          width: 1.5,
                        ),
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

              // --- Preferences & Settings ---
              Text('SETTINGS & PREFERENCES', style: AppTextStyles.eyebrow),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.security,
                title: 'Privacy Settings',
                subtitle: 'Data visibility, blocked contacts, encryption keys',
                onTap: () {},
              ),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.notifications_none,
                title: 'Notification Settings',
                subtitle: 'Push alerts, channel mentions, sound effects',
                onTap: () {},
              ),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.chat_bubble_outline,
                title: 'Chat Settings',
                subtitle: 'Media auto-download, message retention, history',
                onTap: () {},
              ),
              const SizedBox(height: 8),

              SettingTile(
                icon: Icons.palette_outlined,
                title: 'Theme & Appearance',
                subtitle: 'Color schemes, terminal styles, font size',
                onTap: () {},
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
