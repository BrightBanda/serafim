import 'package:flutter/material.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// One choice in the attachment sheet.
class AttachOption {
  const AttachOption({
    required this.value,
    required this.icon,
    required this.label,
    required this.color,
    this.disabledReason,
  });

  final String value;
  final IconData icon;
  final String label;
  final Color color;

  /// Dims it. Tapping it still closes the sheet, so the chat can say why.
  final String? disabledReason;
}

/// The sheet behind the paperclip: a grid of what can be added to the chat.
/// Returns the [AttachOption.value] tapped, or null.
Future<String?> showAttachmentSheet(
  BuildContext context, {
  required List<AttachOption> options,
  Widget? footer,
}) => showSettledSheet<String>(
  context: context,
  backgroundColor: AppColors.paperAlt,
  shape: const RoundedRectangleBorder(),
  builder: (ctx) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 3, color: AppColors.lineSoft),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (_, box) {
              final width = (box.maxWidth - 8 * 3) / 4;
              return Wrap(
                spacing: 8,
                runSpacing: 14,
                children: [
                  for (final o in options)
                    SizedBox(
                      width: width,
                      child: _Tile(
                        option: o,
                        onTap: () => Navigator.pop(ctx, o.value),
                      ),
                    ),
                ],
              );
            },
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer],
        ],
      ),
    ),
  ),
);

class _Tile extends StatelessWidget {
  const _Tile({required this.option, required this.onTap});

  final AttachOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final off = option.disabledReason != null;
    return GestureDetector(
      key: ValueKey('attach-${option.value}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        enabled: !off,
        label: option.label,
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.paper,
                border: Border.all(color: AppColors.lineSoft, width: 1.5),
              ),
              child: Icon(
                option.icon,
                size: 24,
                color: off ? AppColors.lineSoft : option.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: AppTextStyles.smallDim.copyWith(
                color: off ? AppColors.lineSoft : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
