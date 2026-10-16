import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/app_settings.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ChatSettingsPage extends ConsumerWidget {
  const ChatSettingsPage({super.key});

  Future<void> _setRetention(
    BuildContext context,
    WidgetRef ref,
    int days,
  ) async {
    final current = ref.read(settingsProvider).retentionDays;
    if (days == current) return;

    // Shortening retention deletes data, so say so before doing it.
    final shortening = days != 0 && (current == 0 || days < current);
    if (shortening) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.paperAlt,
          title: Text(
            'Remove old messages?',
            style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
          ),
          content: Text(
            'Messages and images older than ${retentionChoices[days]!.toLowerCase()} '
            'will be permanently removed from this device. The other person '
            'keeps their copy.',
            style: AppTextStyles.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    ref.read(settingsProvider.notifier).setRetentionDays(days);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsScaffold(
      title: 'CHAT SETTINGS',
      children: [
        const SettingsSectionLabel('Photo quality when sending'),
        for (final quality in ImageQuality.values)
          SettingsChoiceRow(
            title: quality.label,
            subtitle: '${quality.description} (up to ${quality.maxSide}px)',
            selected: settings.imageQuality == quality,
            onTap: () => notifier.setImageQuality(quality),
          ),
        const SettingsNote(
          'Photos are shrunk on your device before they are sent. Pictures '
          'stay on the devices of the people in the conversation.',
        ),
        const SettingsSectionLabel('Keep messages for'),
        for (final entry in retentionChoices.entries)
          SettingsChoiceRow(
            title: entry.value,
            selected: settings.retentionDays == entry.key,
            onTap: () => _setRetention(context, ref, entry.key),
          ),
        const SettingsNote(
          'Older messages and images are cleared from this device only, when '
          'the app starts and when you change this setting.',
        ),
      ],
    );
  }
}
