import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/small_action_button.dart';
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
        const _PushStatusCard(),
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

/// Whether this phone is set up for push, with a button that asks the server to
/// send a real notification — so a problem shows up here, in words, instead of
/// as silence.
class _PushStatusCard extends ConsumerStatefulWidget {
  const _PushStatusCard();

  @override
  ConsumerState<_PushStatusCard> createState() => _PushStatusCardState();
}

class _PushStatusCardState extends ConsumerState<_PushStatusCard> {
  bool _sending = false;
  String? _result;
  bool _resultOk = false;

  Future<void> _sendTest() async {
    setState(() {
      _sending = true;
      _result = null;
    });
    String message;
    var ok = false;
    try {
      final result = await ref.read(pushServiceProvider).sendTest();
      ok = result.ok;
      message = result.ok
          ? 'Sent. A notification should appear in a moment. Put the app in '
                'the background to see it.'
          : result.reason ?? 'The test notification could not be sent.';
    } catch (error) {
      message = humanError(error);
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = message;
      _resultOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(pushStatusProvider);
    final enabled = ref.watch(
      settingsProvider.select((s) => s.pushNotifications),
    );

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(
          color: status.ok && enabled ? AppColors.teal : AppColors.lineSoft,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THIS PHONE', style: AppTextStyles.fieldLabel),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                status.ok && enabled ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: status.ok && enabled
                    ? AppColors.tealPale
                    : AppColors.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  enabled
                      ? status.message
                      : 'Push notifications are turned off.',
                  style: AppTextStyles.body.copyWith(color: AppColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SmallActionButton(
            label: 'Send test notification',
            icon: Icons.notifications_active_outlined,
            busy: _sending,
            onPressed: enabled ? _sendTest : null,
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Text(
              _result!,
              style: AppTextStyles.body.copyWith(
                color: _resultOk ? AppColors.tealPale : AppColors.rustPale,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
