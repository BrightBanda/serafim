import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/update/update_flow_panel.dart';

/// Shows [child] unless this version is below a mandatory release, in which
/// case the blocking update screen takes its place (before sign-in too).
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateCheckProvider).value;
    if (status != null && status.mustUpdate) {
      return MandatoryUpdateScreen(update: status.available);
    }
    return child;
  }
}

/// Blocks an outdated version until it updates — but never traps anyone:
/// every failure has Try again, and the release page always opens in the
/// browser as a way out.
class MandatoryUpdateScreen extends ConsumerWidget {
  const MandatoryUpdateScreen({super.key, required this.update});

  /// Null when the release details couldn't be loaded.
  final AppUpdate? update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = update;
    final repo = ref.watch(updateServiceProvider).repo;
    final page = u?.releasePage ?? 'https://github.com/$repo/releases/latest';

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SerafimMark(size: 64)),
                  const SizedBox(height: 18),
                  Text(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayHeading,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    u == null
                        ? 'This version of Serafim is no longer supported. '
                              'Install the latest version to continue.'
                        : 'This version of Serafim is no longer supported. '
                              'Install ${u.versionName} to continue.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.text),
                  ),
                  if (u != null && u.changelog.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text("WHAT'S NEW", style: AppTextStyles.eyebrow),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.paperAlt,
                        border: Border.all(
                          color: AppColors.lineSoft,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        u.changelog,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (u != null)
                    UpdateFlowPanel(update: u)
                  else
                    TextButton(
                      onPressed: () =>
                          ref.read(updateCheckProvider.notifier).refresh(),
                      child: Text('Try again', style: AppTextStyles.linkText),
                    ),
                  const SizedBox(height: 8),
                  // Always available, whatever state the download is in.
                  TextButton.icon(
                    onPressed: () => openLink(Uri.parse(page)),
                    icon: Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: AppColors.primaryPale,
                    ),
                    label: Text(
                      'Download from GitHub in the browser',
                      style: AppTextStyles.linkText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
