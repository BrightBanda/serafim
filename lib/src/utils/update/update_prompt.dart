import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/update/update_flow_panel.dart';

/// The launch-time "new version" sheet. "Not now" hides this version until a
/// newer one comes out.
Future<void> showUpdatePrompt(BuildContext context, AppUpdate update) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paperAlt,
    shape: Border(top: BorderSide(color: AppColors.line, width: 2)),
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final busy = ref.watch(updateFlowProvider).busy;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Serafim ${update.versionName} is here',
                    style: AppTextStyles.displayHeading,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    update.changelog.isEmpty
                        ? 'Fixes and improvements.'
                        : update.changelog,
                    style: AppTextStyles.body.copyWith(color: AppColors.text),
                  ),
                  const SizedBox(height: 16),
                  UpdateFlowPanel(update: update),
                  if (!busy)
                    TextButton(
                      onPressed: () {
                        ref
                            .read(updateCheckProvider.notifier)
                            .dismiss(update.versionCode);
                        Navigator.pop(ctx);
                      },
                      child: Text('Not now', style: AppTextStyles.linkText),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
