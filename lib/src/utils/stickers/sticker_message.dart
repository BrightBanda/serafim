import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/stickers/sticker_view.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// A sticker in the conversation: no bubble, just the (animated) sticker with
/// a small label underneath and, for your own, its delivery state.
class StickerMessage extends StatelessWidget {
  const StickerMessage({
    super.key,
    required this.stickerId,
    required this.label,
    required this.outgoing,
    this.status,
    this.onTap,
    this.onLongPress,
  });

  final String stickerId;
  final String label;
  final bool outgoing;
  final ChatMessageStatus? status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final state = switch (status) {
      ChatMessageStatus.sending => ' · sending',
      ChatMessageStatus.sent => ' · sent',
      ChatMessageStatus.delivered => ' · delivered',
      ChatMessageStatus.read => ' · read',
      ChatMessageStatus.failed => ' · failed',
      null => '',
    };
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            StickerView(stickerId: stickerId, size: 124, animate: true),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              // Readable on any chat background.
              color: AppColors.paper.withValues(alpha: 0.8),
              child: Text(
                '$label$state',
                style: AppTextStyles.fieldLabel.copyWith(
                  fontSize: 8,
                  color: status == ChatMessageStatus.failed
                      ? AppColors.rustPale
                      : AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
