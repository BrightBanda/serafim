import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// A single row in the chat list. UI only — [onTap] is a plain
/// callback, opening the actual thread is the caller's job.
class ChatRow extends StatelessWidget {
  const ChatRow({
    super.key,
    required this.name,
    required this.preview,
    required this.time,
    this.isGroup = false,
    this.unread = false,
    this.onTap,
  });

  final String name;
  final String preview;
  final String time;
  final bool isGroup;
  final bool unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.line,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            AvatarThumb(isGroup: isGroup),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: AppTextStyles.fieldLabel.copyWith(fontSize: 8.5),
                ),
                if (unread) ...[
                  const SizedBox(height: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.tealPale,
                      border: Border.all(color: AppColors.line, width: 1),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
