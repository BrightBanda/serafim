import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/privacy_policy_page.dart';
import 'package:serafim/src/presentation/view/terms_of_service_page.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/setting_tile.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// About Serafim: the version, who made it, and the Terms of Service and
/// Privacy Policy.
class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  static void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'ABOUT',
      children: [
        const _AboutCard(),
        const SizedBox(height: 16),
        SettingTile(
          icon: Icons.description_outlined,
          title: 'Terms of Service',
          subtitle: 'The rules for using Serafim',
          onTap: () => _open(context, const TermsOfServicePage()),
        ),
        const SizedBox(height: 8),
        SettingTile(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy Policy',
          subtitle: 'What we collect and why',
          onTap: () => _open(context, const PrivacyPolicyPage()),
        ),
      ],
    );
  }
}

/// Which version this is, and who made it.
class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  static const developer = 'Bright Banda';
  static const year = '2026';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read from the installed app (Android), so it is always the real one.
    final installed = ref.watch(installedVersionProvider);
    final version = installed.when(
      data: (v) => v == null ? 'Unknown' : v.name,
      loading: () => '…',
      error: (_, __) => 'Unknown',
    );

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: AppTextStyles.smallDim),
          const Spacer(),
          Text(
            value,
            style: AppTextStyles.body.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.lineSoft, width: 1.5),
      ),
      child: Column(
        children: [
          row('Version', version),
          row('Developer', developer),
          row('Year', year),
        ],
      ),
    );
  }
}
