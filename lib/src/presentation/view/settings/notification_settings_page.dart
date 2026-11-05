import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/settings/sound_settings_page.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/settings_widgets.dart';

class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsScaffold(
      title: 'NOTIFICATIONS',
      children: [
        const SettingsSectionLabel('When the app is closed'),
        SettingsSwitchRow(
          title: 'Push notifications',
          subtitle:
              'Get a notification for new messages even when Serafim is '
              'not open.',
          value: settings.pushNotifications,
          onChanged: notifier.setPushNotifications,
        ),
        SettingsSwitchRow(
          title: 'Show message previews',
          subtitle:
              'Include the message text in the notification. When off, '
              'you only see who it is from.',
          value: settings.pushPreviews,
          onChanged: settings.pushNotifications
              ? notifier.setPushPreviews
              : null,
        ),
        const SettingsNote(
          "You can also manage notifications in your phone's settings.",
        ),
        const SettingsSectionLabel('While the app is open'),
        SettingsSwitchRow(
          title: 'Message banners',
          subtitle: 'Show a banner when a message arrives in another screen.',
          value: settings.inAppAlerts,
          onChanged: notifier.setInAppAlerts,
        ),
        ListTile(
          key: const ValueKey('open-sounds'),
          contentPadding: EdgeInsets.zero,
          title: Text('Sounds', style: AppTextStyles.fieldInput),
          subtitle: Text(
            'Message received and sent, typing, notifications. Pick your own.',
            style: AppTextStyles.smallDim,
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.textDim),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SoundSettingsPage()),
          ),
        ),
        SettingsSwitchRow(
          title: 'Wings always get through',
          subtitle:
              'Messages from your Wings still show a banner, even with '
              'banners turned off.',
          value: settings.wingsBreakThrough,
          onChanged: notifier.setWingsBreakThrough,
        ),
      ],
    );
  }
}
