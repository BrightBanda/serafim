import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/emoji.dart';
import 'package:serafim/src/utils/links.dart';
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
    this.imagePath,
    this.deleted = false,
    this.onLongPress,
    this.onSaveImage,
    this.onDeleteImage,
    this.quote,
    this.footer,
    this.forwarded = false,
  });

  /// Shown under the text (e.g. a link preview card).
  final Widget? footer;

  /// The message this one replies to, shown above the content.
  final ReplyQuoteData? quote;

  /// Adds a Delete button to the full-screen image viewer.
  final Future<void> Function()? onDeleteImage;

  /// Deleted for everyone: shows a placeholder instead of the content.
  final bool deleted;

  /// This copy is one the person forwarded to another chat. Only the
  /// sender's own copy carries the label.
  final bool forwarded;

  /// Press-and-hold on the bubble (message actions).
  final VoidCallback? onLongPress;

  /// Adds a Download button to the full-screen image viewer.
  final Future<void> Function()? onSaveImage;

  /// Local file path of an attached image, if any.
  final String? imagePath;

  final String who;
  final String message;
  final ChatBubbleSide side;

  /// Delivery status to show under the message. Only meaningful — and only
  /// rendered — for outgoing bubbles; incoming messages never show one.
  final ChatMessageStatus? status;

  /// The message text. A few emoji on their own are drawn large; emoji among
  /// words are a little larger than the letters.
  Widget _text(bool isOut) {
    final style = AppTextStyles.body.copyWith(
      color: isOut ? Colors.white : AppColors.text,
      fontSize: 11,
      height: 1.5,
    );
    final only = emojiOnlyCount(message);
    final jumbo = only == null ? null : jumboEmojiSize(only);
    if (jumbo != null && imagePath == null) {
      return Text(
        message.trim(),
        style: style.copyWith(fontSize: jumbo, height: 1.2),
      );
    }
    return LinkifiedText(
      message,
      style: style,
      emojiScale: emojiInTextScale,
      linkColor: isOut ? const Color(0xFFEAF0FF) : AppColors.primaryPale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOut = side == ChatBubbleSide.outgoing;
    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            gradient: isOut
                ? LinearGradient(
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
            boxShadow: [
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
              if (quote != null && !deleted) ...[
                _ReplyQuote(data: quote!, outgoing: isOut),
                const SizedBox(height: 6),
              ],
              if (forwarded && !deleted) ...[
                Text(
                  '↪ Forwarded',
                  style: AppTextStyles.smallDim.copyWith(
                    color: isOut ? const Color(0xFFDBE4FB) : AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              if (deleted)
                Text(
                  'This message was deleted',
                  style: AppTextStyles.body.copyWith(
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                    color: isOut ? const Color(0xFFDBE4FB) : AppColors.textDim,
                  ),
                )
              else ...[
                if (imagePath != null) ...[
                  GestureDetector(
                    onTap: () => _openFullScreen(
                      context,
                      imagePath!,
                      onSaveImage,
                      onDeleteImage,
                    ),
                    child: ConstrainedBox(
                      // Photos are big; GIFs and stickers are a small
                      // thing you glance at, so they are kept small.
                      constraints: isSmallMedia(imagePath!)
                          ? const BoxConstraints(maxHeight: 130, maxWidth: 170)
                          : const BoxConstraints(maxHeight: 260),
                      child: Image.file(
                        File(imagePath!),
                        fit: isSmallMedia(imagePath!)
                            ? BoxFit.contain
                            : BoxFit.cover,
                        cacheWidth: isSmallMedia(imagePath!) ? 340 : 800,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.broken_image_outlined, size: 28),
                        ),
                      ),
                    ),
                  ),
                  if (message.isNotEmpty) const SizedBox(height: 6),
                ],
                if (message.isNotEmpty) _text(isOut),
                if (footer != null) footer!,
              ],
              if (isOut && status != null && !deleted) ...[
                const SizedBox(height: 4),
                _StatusRow(status: status!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _openFullScreen(
  BuildContext context,
  String path,
  Future<void> Function()? onSave,
  Future<void> Function()? onDelete,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  Navigator.of(context).pop();
                  onDelete();
                },
              ),
            if (onSave != null)
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download_outlined),
                onPressed: onSave,
              ),
          ],
        ),
        body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
      ),
    ),
  );
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

/// What a reply quotes: who wrote the original and a short snippet. Built by
/// the thread page from the local message list.
class ReplyQuoteData {
  const ReplyQuoteData({
    required this.author,
    required this.snippet,
    this.available = true,
    this.onTap,
  });

  final String author;
  final String snippet;

  /// False when the original was deleted/removed; shown muted.
  final bool available;
  final VoidCallback? onTap;
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.data, required this.outgoing});

  final ReplyQuoteData data;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final fg = outgoing ? Colors.white : AppColors.text;

    return GestureDetector(
      onTap: data.available ? data.onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: outgoing ? 0.18 : 0.25),
          border: Border(
            left: BorderSide(
              color: outgoing ? AppColors.primaryPale : AppColors.tealPale,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.author,
              style: AppTextStyles.fieldLabel.copyWith(
                fontSize: 8.5,
                color: outgoing ? AppColors.primaryPale : AppColors.tealPale,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              data.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontSize: 10.5,
                height: 1.35,
                fontStyle: data.available ? null : FontStyle.italic,
                color: fg.withValues(alpha: data.available ? 0.9 : 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// GIFs, WebP and PNG (what keyboards insert as GIFs and stickers) are shown
/// small; JPEG photos from the camera and gallery are shown large.
bool isSmallMedia(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.gif') || p.endsWith('.webp') || p.endsWith('.png');
}
