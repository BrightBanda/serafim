import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

class PrivacySettingsPage extends ConsumerWidget {
  const PrivacySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileViewModelProvider).value;

    Future<void> setAllowRequests(bool allow) async {
      final error = await ref
          .read(profileViewModelProvider.notifier)
          .updateProfile(ProfileUpdateRequest(allowFriendRequests: allow));
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.rust),
        );
      }
    }

    return SettingsScaffold(
      title: 'PRIVACY',
      children: [
        const SettingsSectionLabel('Messaging'),
        SettingsSwitchRow(
          title: 'Read receipts',
          subtitle: 'Let people see when you have read their messages.',
          value: settings.sendReadReceipts,
          onChanged: ref.read(settingsProvider.notifier).setSendReadReceipts,
        ),
        const SettingsNote(
          'This only controls what you send. You will still see when others '
          'have read your messages if they have receipts on.',
        ),
        const SettingsSectionLabel('Who can reach you'),
        SettingsSwitchRow(
          title: 'Allow friend requests',
          subtitle: profile == null
              ? 'Create your profile to change this.'
              : 'Turn off to stop new people sending you friend requests.',
          value: profile?.allowFriendRequests ?? true,
          onChanged: profile == null ? null : setAllowRequests,
        ),
        const SettingsNote(
          'Existing friends and pending requests are not affected. Anyone can '
          'still message you or follow you; attachments are only ever allowed '
          'between friends.',
        ),
      ],
    );
  }
}
