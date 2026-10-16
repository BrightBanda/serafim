import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Shared frame for a settings screen: top bar with back, scrolling body.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: title,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: children,
        ),
      ),
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Text(text.toUpperCase(), style: AppTextStyles.eyebrow),
  );
}

/// Small explanatory paragraph under a group of settings.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Text(text, style: AppTextStyles.smallDim),
  );
}

BoxDecoration _box({bool selected = false}) => BoxDecoration(
  color: AppColors.paperAlt,
  border: Border.all(
    color: selected ? AppColors.primary : AppColors.lineSoft,
    width: 1.5,
  ),
);

/// A titled on/off setting. A null [onChanged] shows it disabled.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    // A Material (not a coloured Container) so the tile's ink splash is visible.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.paperAlt,
        shape: Border.all(color: AppColors.lineSoft, width: 1.5),
        child: SwitchListTile(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.primary,
          inactiveThumbColor: AppColors.textDim,
          inactiveTrackColor: AppColors.paper,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          title: Text(
            title,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.bold,
              color: onChanged == null ? AppColors.textDim : AppColors.text,
            ),
          ),
          subtitle: Text(subtitle, style: AppTextStyles.smallDim),
        ),
      ),
    );
  }
}

/// One option in a pick-one list. The chosen one gets the blue outline.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: _box(selected: selected),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: AppTextStyles.smallDim),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textDim,
            ),
          ],
        ),
      ),
    );
  }
}
