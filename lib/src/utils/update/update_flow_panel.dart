import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The Update button and everything after it: download progress (with
/// Cancel), checking, the "Install unknown apps" explanation, errors with
/// Retry, and a way out to the release page. Used by the chat card, the
/// launch prompt and the blocking screen alike.
class UpdateFlowPanel extends ConsumerWidget {
  const UpdateFlowPanel({super.key, required this.update});

  final AppUpdate update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedVersionProvider);
    // The size of the build this phone would download.
    final abis = ref.watch(deviceAbisProvider).value ?? const <String>[];
    final forPhone = update.forDevice(abis);
    final flow = ref.watch(updateFlowProvider);
    final controller = ref.read(updateFlowProvider.notifier);

    final version = installed.value;
    if (installed.isLoading) {
      return const _Line(text: 'Checking your version…', spinner: true);
    }
    if (version == null) {
      return const _Line(
        text: 'Updates are installed from Serafim on Android.',
      );
    }
    if (!update.isNewerThan(version)) {
      return _Line(
        text: version.code == update.versionCode
            ? 'Installed'
            : 'Up to date (you have ${version.name})',
        icon: Icons.check_circle_outline,
      );
    }

    final mine = flow.update?.versionCode == update.versionCode;
    if (!mine && flow.busy) {
      return const _Line(text: 'Another update is being installed…');
    }
    final phase = mine ? flow.phase : UpdatePhase.idle;

    switch (phase) {
      case UpdatePhase.idle:
        if (abis.isNotEmpty && forPhone == null) {
          return const _Line(
            text: "This release isn't available for your phone's processor.",
          );
        }
        final size = (forPhone ?? update).sizeBytes;
        return SerafimButton(
          label: size > 0 ? 'Update · ${formatBytes(size)}' : 'Update',
          onPressed: () => controller.start(update),
        );
      case UpdatePhase.preparing:
        return const _Line(text: 'Getting ready…', spinner: true);
      case UpdatePhase.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: flow.progress,
              minHeight: 6,
              color: AppColors.primary,
              backgroundColor: AppColors.paperRaised,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    flow.total > 0
                        ? 'Downloading ${formatBytes(flow.received)} of '
                              '${formatBytes(flow.total)}'
                        : 'Downloading ${formatBytes(flow.received)}',
                    style: AppTextStyles.smallDim,
                  ),
                ),
                TextButton(
                  onPressed: controller.cancel,
                  child: Text('Cancel', style: AppTextStyles.linkText),
                ),
              ],
            ),
          ],
        );
      case UpdatePhase.verifying:
        return const _Line(text: 'Checking the download…', spinner: true);
      case UpdatePhase.installing:
        return const _Line(
          text: 'Waiting for Android to install it…',
          spinner: true,
        );
      case UpdatePhase.needsPermission:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'One more step: allow Serafim to install updates. Android asks '
              'this once for apps that update themselves outside the Play '
              'Store. Turn on "Allow from this source", then come back — the '
              'update continues by itself.',
              style: AppTextStyles.body.copyWith(color: AppColors.text),
            ),
            const SizedBox(height: 10),
            SerafimButton(
              label: 'Open settings',
              onPressed: controller.openInstallSettings,
            ),
            TextButton(
              onPressed: controller.continueAfterPermission,
              child: Text("I've allowed it", style: AppTextStyles.linkText),
            ),
          ],
        );
      case UpdatePhase.failed:
        final error = flow.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error?.message ?? 'The update failed.',
              style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
            ),
            const SizedBox(height: 10),
            if (error == null || error.retryable)
              SerafimButton(
                label: 'Try again',
                onPressed: () => controller.start(update),
              ),
            TextButton(
              onPressed: () => openLink(Uri.parse(update.releasePage)),
              child: Text(
                'Open the release page',
                style: AppTextStyles.linkText,
              ),
            ),
          ],
        );
    }
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, this.spinner = false, this.icon});

  final String text;
  final bool spinner;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (spinner)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: AppColors.tealPale),
        if (spinner || icon != null) const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body.copyWith(color: AppColors.text),
          ),
        ),
      ],
    );
  }
}
