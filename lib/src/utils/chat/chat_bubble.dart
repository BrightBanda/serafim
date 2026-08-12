import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Which side a bubble renders on.
enum ChatBubbleSide { incoming, outgoing }

/// A single chat message bubble. Purely presentational — takes the
/// text to show, no message-sending logic lives here.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.who,
    required this.message,
    required this.side,
  });

  final String who;
  final String message;
  final ChatBubbleSide side;

  @override
  Widget build(BuildContext context) {
    final isOut = side == ChatBubbleSide.outgoing;
    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
        decoration: BoxDecoration(
          gradient: isOut
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDeep],
                )
              : null,
          color: isOut ? null : AppColors.paperRaised,
          border: Border.all(
            color: isOut ? AppColors.line : AppColors.lineSoft,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: AppColors.line,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              who,
              style: AppTextStyles.fieldLabel.copyWith(
                fontSize: 8,
                color: isOut ? const Color(0xFFDBE4FB) : AppColors.tealPale,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              message,
              style: AppTextStyles.body.copyWith(
                color: isOut ? Colors.white : AppColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
