import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/settings_providers.dart';
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
          'You can also manage notifications for Serafim in your phone\'s '
          'system settings. Pushes are sent only when you are not already '
          'connected, so you will not get one for a chat you are looking at.',
        ),
        const SettingsSectionLabel('While the app is open'),
        SettingsSwitchRow(
          title: 'Message banners',
          subtitle: 'Show a banner when a message arrives in another screen.',
          value: settings.inAppAlerts,
          onChanged: notifier.setInAppAlerts,
        ),
        SettingsSwitchRow(
          title: 'Sound',
          subtitle: 'Play a sound with each banner.',
          value: settings.alertSound,
          onChanged: settings.inAppAlerts ? notifier.setAlertSound : null,
        ),
      ],
    );
  }
}
