import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/chat_image_gallery.dart';
import 'package:serafim/src/utils/emoji.dart';
import 'package:serafim/src/utils/limited_gif.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Which side a bubble renders on.
enum ChatBubbleSide { incoming, outgoing }

/// Delivery state of an outgoing message. Kept local to this widget (rather
/// than importing the Isar domain model's MessageStatus) so ChatBubble stays
/// purely presentational with no data-layer dependency.
enum ChatMessageStatus { sending, sent, delivered, read, failed }

class ChatImageAttachment {
  const ChatImageAttachment({
    required this.path,
    this.key,
    this.onTap,
    this.onLongPress,
    this.onSave,
    this.onDelete,
  });

  final String path;
  final Key? key;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onDelete;
}

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
    this.imageAttachments = const [],
    this.onTapImage,
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

  /// Taps on an attached image/GIF. When provided, used instead of opening
  /// the full-screen viewer (e.g. to show forward/save/delete options).
  final VoidCallback? onTapImage;

  /// Adds a Download button to the full-screen image viewer.
  final Future<void> Function()? onSaveImage;

  /// Local file path of an attached image, if any.
  final String? imagePath;
  final List<ChatImageAttachment> imageAttachments;

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
                if (imageAttachments.length > 1) ...[
                  ChatImageGrid(images: imageAttachments),
                  if (message.isNotEmpty) const SizedBox(height: 6),
                ],
                if (imagePath != null) ...[
                  GestureDetector(
                    onTap:
                        onTapImage ??
                        () => openChatImageGallery(context, [
                          (
                            path: imagePath!,
                            onSave: onSaveImage,
                            onDelete: onDeleteImage,
                          ),
                        ]),
                    child: ConstrainedBox(
                      // Photos are big; GIFs and stickers are a small
                      // thing you glance at, so they are kept small. A
                      // scribble is shown whole, in a square.
                      constraints: isScribble(imagePath!)
                          ? const BoxConstraints(maxHeight: 220, maxWidth: 220)
                          : isSmallMedia(imagePath!)
                          ? const BoxConstraints(maxHeight: 130, maxWidth: 170)
                          : const BoxConstraints(maxHeight: 260),
                      child: isGifPath(imagePath!)
                          ? LimitedGif(
                              path: imagePath!,
                              cacheWidth: 340,
                              errorBuilder: (_) => const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 28,
                                ),
                              ),
                            )
                          : Image.file(
                              File(imagePath!),
                              fit:
                                  isSmallMedia(imagePath!) ||
                                      isScribble(imagePath!)
                                  ? BoxFit.contain
                                  : BoxFit.cover,
                              cacheWidth: isScribble(imagePath!)
                                  ? 520
                                  : (isSmallMedia(imagePath!) ? 340 : 800),
                              errorBuilder: (_, __, ___) => const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 28,
                                ),
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

/// Pictures sent together: at most four tiles in a compact two-column grid
/// (an odd one out spans the row); with more, the fourth shows "+N" for the
/// rest. Tapping any tile opens them all, to swipe through.
class ChatImageGrid extends StatelessWidget {
  const ChatImageGrid({super.key, required this.images});

  final List<ChatImageAttachment> images;

  static const maxTiles = 4;
  static const gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.5).clamp(150.0, 230.0);
    final tile = (width - gap) / 2;
    final shown = images.length > maxTiles ? maxTiles : images.length;
    final hidden = images.length - shown;
    final cache = (tile * MediaQuery.devicePixelRatioOf(context)).round();

    Widget cell(int i, double w) {
      final image = images[i];
      final more = i == shown - 1 && hidden > 0;
      return GestureDetector(
        key: image.key,
        onTap:
            image.onTap ??
            () => openChatImageGallery(context, [
              for (final m in images)
                (path: m.path, onSave: m.onSave, onDelete: m.onDelete),
            ], initialIndex: i),
        onLongPress: image.onLongPress,
        child: SizedBox(
          width: w,
          height: tile,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isGifPath(image.path))
                // Plays once in the grid; fully when opened.
                LimitedGif(
                  path: image.path,
                  loops: 1,
                  fit: BoxFit.cover,
                  cacheWidth: cache,
                  showReplay: false,
                  errorBuilder: (_) => Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textDim,
                  ),
                )
              else
                Image.file(
                  File(image.path),
                  fit: BoxFit.cover,
                  cacheWidth: cache,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: AppColors.paperRaised,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              if (more)
                ColoredBox(
                  color: const Color(0x8C000000),
                  child: Center(
                    child: Text(
                      '+${hidden + 1}',
                      key: const ValueKey('chat-image-grid-more'),
                      style: AppTextStyles.displayHeading.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('chat-image-grid'),
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < shown; row += 2) ...[
            if (row > 0) const SizedBox(height: gap),
            row + 1 < shown
                ? Row(
                    children: [
                      cell(row, tile),
                      const SizedBox(width: gap),
                      cell(row + 1, tile),
                    ],
                  )
                : cell(row, width),
          ],
        ],
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

/// A hand-drawn scribble (saved as `<id>.scribble.png`).
bool isScribble(String path) => path.toLowerCase().endsWith('.scribble.png');

/// GIFs, WebP and PNG (what keyboards insert as GIFs and stickers) are shown
/// small; JPEG photos from the camera and gallery are shown large. A scribble
/// is a PNG too, but a drawing to read, so it is not small.
bool isSmallMedia(String path) {
  final p = path.toLowerCase();
  if (isScribble(p)) return false;
  return p.endsWith('.gif') || p.endsWith('.webp') || p.endsWith('.png');
}
