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

    Future<void> save(ProfileUpdateRequest request) async {
      final error = await ref
          .read(profileViewModelProvider.notifier)
          .updateProfile(request);
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
        const SettingsNote("You'll still see other people's read receipts."),
        const SettingsSectionLabel('Who can reach you'),
        SettingsSwitchRow(
          title: 'Allow friend requests',
          subtitle: profile == null
              ? 'Create your profile to change this.'
              : 'Turn off to stop new people sending you friend requests.',
          value: profile?.allowFriendRequests ?? true,
          onChanged: profile == null
              ? null
              : (allow) =>
                    save(ProfileUpdateRequest(allowFriendRequests: allow)),
        ),
        const SettingsNote("Existing friends and requests aren't affected."),
        const SettingsSectionLabel('Who can add you to groups'),
        for (final option in GroupAddPrivacy.values)
          SettingsChoiceRow(
            title: option.label,
            subtitle: option.description,
            selected:
                (profile?.groupAddPrivacy ?? GroupAddPrivacy.everyone) ==
                option,
            onTap: profile == null
                ? () {}
                : () => save(ProfileUpdateRequest(groupAddPrivacy: option)),
          ),
        const SettingsSectionLabel('Your profile'),
        SettingsSwitchRow(
          title: 'Lock profile',
          subtitle: profile == null
              ? 'Create your profile to change this.'
              : 'Only your friends can see your friends, followers and following.',
          value: profile?.lockProfile ?? false,
          onChanged: profile == null
              ? null
              : (locked) => save(ProfileUpdateRequest(lockProfile: locked)),
        ),
        const SettingsNote(
          'Your name, photo, bio and interests are always visible.',
        ),
      ],
    );
  }
}
