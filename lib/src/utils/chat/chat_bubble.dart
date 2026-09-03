import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Which side a bubble renders on.
enum ChatBubbleSide { incoming, outgoing }

/// Delivery state of an outgoing message. Kept local to this widget (rather
/// than importing the Isar domain model's MessageStatus) so ChatBubble stays
/// purely presentational with no data-layer dependency.
enum ChatMessageStatus { sending, sent, delivered, read, failed }

/// A single chat message bubble. Purely presentational — takes the
/// text to show, no message-sending logic lives here.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.who,
    required this.message,
    required this.side,
    this.status,
  });

  final String who;
  final String message;
  final ChatBubbleSide side;

  /// Delivery status to show under the message. Only meaningful — and only
  /// rendered — for outgoing bubbles; incoming messages never show one.
  final ChatMessageStatus? status;

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
            if (isOut && status != null) ...[
              const SizedBox(height: 4),
              _StatusRow(status: status!),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status});

  final ChatMessageStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusIcon(status: status),
        const SizedBox(width: 3),
        Text(
          _label(status),
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 8,
            color: Color(0xFFDBE4FB),
          ),
        ),
      ],
    );
  }

  String _label(ChatMessageStatus s) {
    switch (s) {
      case ChatMessageStatus.sending:
        return 'sending';
      case ChatMessageStatus.sent:
        return 'sent';
      case ChatMessageStatus.delivered:
        return 'delivered';
      case ChatMessageStatus.read:
        return 'read';
      case ChatMessageStatus.failed:
        return 'failed';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final ChatMessageStatus status;

  @override
  Widget build(BuildContext context) {
    const size = 10.0;
    switch (status) {
      case ChatMessageStatus.sending:
        return const SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFFDBE4FB),
          ),
        );
      case ChatMessageStatus.sent:
        return const Icon(Icons.check, size: size, color: Color(0xFFDBE4FB));
      case ChatMessageStatus.delivered:
        return const Icon(Icons.done_all, size: size, color: Color(0xFFDBE4FB));
      case ChatMessageStatus.read:
        return Icon(Icons.done_all, size: size, color: AppColors.tealPale);
      case ChatMessageStatus.failed:
        return Icon(
          Icons.error_outline,
          size: size,
          color: Colors.red.shade300,
        );
    }
  }
}
