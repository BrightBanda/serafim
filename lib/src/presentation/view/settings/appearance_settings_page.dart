import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/app_settings.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsScaffold(
      title: 'APPEARANCE',
      children: [
        const SettingsSectionLabel('Theme'),
        for (final choice in ThemeChoice.values)
          SettingsChoiceRow(
            title: choice.label,
            subtitle: choice.description,
            selected: settings.themeChoice == choice,
            onTap: () => notifier.setThemeChoice(choice),
          ),
        const SettingsNote('Changes the whole app straight away.'),
        const SettingsSectionLabel('Text size'),
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.lineSoft, width: 1.5),
          ),
          child: Text(
            'The quick brown fox jumps over the lazy dog.',
            style: AppTextStyles.body.copyWith(color: AppColors.text),
          ),
        ),
        for (final size in TextSize.values)
          SettingsChoiceRow(
            title: size.label,
            selected: settings.textSize == size,
            onTap: () => notifier.setTextSize(size),
          ),
        const SettingsNote('Applies everywhere in the app straight away.'),
      ],
    );
  }
}
