import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/utils/halo_style.dart';
import 'package:serafim/src/utils/wing_mark.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// How long a halo can be lit for, as offered.
const List<(String, int)> haloChoices = [
  ('30 minutes', 30),
  ('1 hour', 60),
  ('3 hours', 180),
  ('8 hours', 480),
];

/// Opens the Halo controls: light it for a while, or put it out.
Future<void> showHaloSheet(BuildContext context, WidgetRef ref) {
  return showSettledSheet<void>(
    context: context,
    backgroundColor: AppColors.paperAlt,
    shape: const RoundedRectangleBorder(),
    builder: (_) => const _HaloSheet(),
  );
}

class _HaloSheet extends ConsumerStatefulWidget {
  const _HaloSheet();

  @override
  ConsumerState<_HaloSheet> createState() => _HaloSheetState();
}

class _HaloSheetState extends ConsumerState<_HaloSheet> {
  /// Show it to Wings only, instead of every friend.
  late bool _wingsOnly = ref.read(myHaloAudienceProvider);

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() job,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await job();
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lit = ref.watch(myHaloLitProvider);
    final until = ref.watch(myHaloProvider);
    final local = until?.toLocal();
    final clock = local == null
        ? ''
        : '${local.hour.toString().padLeft(2, '0')}:'
              '${local.minute.toString().padLeft(2, '0')}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.brightness_high, size: 20, color: haloColor),
                const SizedBox(width: 8),
                Text('HALO', style: AppTextStyles.eyebrow),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lit
                  ? 'Your halo is lit until $clock. '
                        '${_wingsOnly ? 'Your Wings' : 'Friends'} see a glow '
                        'around your photo.'
                  : 'Let your friends see you are free to chat. A glow appears '
                        'around your photo, for friends only, and it switches '
                        'itself off.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  key: const ValueKey('halo-audience-friends'),
                  label: const Text('All friends'),
                  selected: !_wingsOnly,
                  onSelected: (_) => setState(() => _wingsOnly = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const ValueKey('halo-audience-wings'),
                  avatar: const WingMark(size: 14),
                  label: const Text('Wings only'),
                  selected: _wingsOnly,
                  onSelected: (_) => setState(() => _wingsOnly = true),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, minutes) in haloChoices)
                  OutlinedButton(
                    key: ValueKey('halo-$minutes'),
                    onPressed: () => _run(
                      context,
                      ref,
                      () => ref
                          .read(myHaloProvider.notifier)
                          .light(minutes, wingsOnly: _wingsOnly),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: BorderSide(color: haloColor, width: 1.5),
                      shape: const RoundedRectangleBorder(),
                    ),
                    child: Text(lit ? 'Extend: $label' : label),
                  ),
              ],
            ),
            if (lit) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('halo-off'),
                onPressed: () =>
                    _run(context, ref, ref.read(myHaloProvider.notifier).dim),
                child: Text('Put it out', style: AppTextStyles.linkText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
