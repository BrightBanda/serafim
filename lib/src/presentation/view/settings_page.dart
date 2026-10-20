import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/settings/appearance_settings_page.dart';
import 'package:serafim/src/presentation/view/settings/backup_settings_page.dart';
import 'package:serafim/src/presentation/view/settings/chat_settings_page.dart';
import 'package:serafim/src/presentation/view/settings/notification_settings_page.dart';
import 'package:serafim/src/presentation/view/settings/privacy_settings_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/setting_tile.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// All the app's settings, and logging out. Opened from the menu in the top
/// bar; your profile is a separate page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _logOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Log out?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          'You can sign back in any time.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Settings is a page over the tabs: close it so the sign-in screen is
    // not left underneath.
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    await ref.read(authViewModelProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'SETTINGS',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            SettingTile(
              icon: Icons.security,
              title: 'Privacy Settings',
              subtitle: 'Read receipts, friend requests, lock profile',
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
            const SizedBox(height: 8),
            SettingTile(
              icon: Icons.cloud_upload_outlined,
              title: 'Backup & Restore',
              subtitle: 'Export chats, back up to Google Drive',
              onTap: () => _open(context, const BackupSettingsPage()),
            ),
            const SizedBox(height: 36),
            SerafimButton(
              label: 'Log out',
              onPressed: () => _logOut(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
