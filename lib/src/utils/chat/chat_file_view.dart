import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/voice/voice_math.dart';

/// The inside of a video or audio-file bubble, with one round button for
/// whatever comes next — sending progress, retry, download (with progress),
/// play. A video shows as its preview picture with the button on top; an
/// audio file as a row with its name, size and length.
///
/// Received files are only downloaded when the person taps, since they can
/// be large. Audio plays right in the bubble (through the same player
/// as voice notes, so only one thing plays at a time); a video opens
/// full screen via [onOpenVideo].
class ChatFileView extends ConsumerWidget {
  const ChatFileView({
    super.key,
    required this.message,
    required this.outgoing,
    this.onRetry,
    this.onDownload,
    this.onOpenVideo,
  });

  final LocalMessage message;
  final bool outgoing;
  final VoidCallback? onRetry;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenVideo;

  bool get _isVideo => message.type == MessageType.video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = message.messageId;
    final transfer = ref.watch(fileTransfersProvider.select((m) => m[id]));
    final playback = ref.watch(voicePlayerProvider);
    final path = message.localMediaPath;
    final failed = message.status == MessageStatus.failed && outgoing;
    final isCurrent = playback.messageId == id;

    // On a video's preview the controls are always white.
    final fg = _isVideo || outgoing ? Colors.white : AppColors.text;
    final dim = outgoing ? const Color(0xFFDBE4FB) : AppColors.textDim;
    final what = _isVideo ? 'video' : 'audio';

    final Widget button;
    final String status;
    VoidCallback? action;
    if (transfer != null) {
      final percent = (transfer.progress * 100).round();
      final sending = transfer.direction == FileTransferDirection.upload;
      status = '${sending ? 'Sending' : 'Downloading'} $percent%';
      button = _Round(
        onPicture: _isVideo,
        color: fg,
        semantics:
            '${sending ? 'Sending' : 'Downloading'} $what, '
            '$percent percent',
        child: CircularProgressIndicator(
          value: transfer.progress <= 0 ? null : transfer.progress,
          strokeWidth: 2.5,
          color: fg,
        ),
      );
    } else if (failed) {
      status = "Couldn't send · tap to retry";
      action = onRetry;
      button = _Round(
        onPicture: _isVideo,
        color: AppColors.rustPale,
        semantics: 'Sending failed. Retry',
        onTap: onRetry,
        child: Icon(Icons.refresh, color: AppColors.rustPale, size: 20),
      );
    } else if (path == null) {
      status = message.mediaRemoteId == null
          ? 'Not available'
          : 'Tap to download';
      action = message.mediaRemoteId == null ? null : onDownload;
      button = _Round(
        onPicture: _isVideo,
        color: fg,
        semantics: 'Download $what',
        onTap: message.mediaRemoteId == null ? null : onDownload,
        child: Icon(Icons.download_rounded, color: fg, size: 22),
      );
    } else if (_isVideo) {
      status = message.status == MessageStatus.sending ? 'Sending…' : 'Video';
      action = onOpenVideo;
      button = _Round(
        onPicture: _isVideo,
        color: fg,
        semantics: 'Play video',
        onTap: onOpenVideo,
        child: Icon(Icons.play_arrow_rounded, color: fg, size: 24),
      );
    } else {
      final playing = isCurrent && playback.playing;
      status = isCurrent
          ? '${formatVoiceDuration(playback.position)} / '
                '${formatVoiceDuration(playback.duration)}'
          : 'Audio';
      button = _Round(
        onPicture: _isVideo,
        color: fg,
        semantics: playing ? 'Pause audio' : 'Play audio',
        onTap: () => ref
            .read(voicePlayerProvider.notifier)
            .toggle(id, path, durationMs: message.durationMs),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: fg,
          size: 24,
        ),
      );
    }

    final details = [
      if (message.fileSize case final size?) formatFileSize(size),
      if (message.durationMs case final ms? when ms > 0 && !isCurrent)
        formatVoiceDuration(Duration(milliseconds: ms)),
    ].join(' · ');

    if (_isVideo) {
      return _VideoPreview(
        thumbnailPath: message.thumbnailPath,
        button: button,
        caption: [
          if (transfer != null || failed || path == null) status,
          if (details.isNotEmpty) details,
        ].join(' · '),
        failed: failed,
        onTap: action,
      );
    }

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          button,
          const SizedBox(width: 10),
          Icon(
            _isVideo ? Icons.movie_outlined : Icons.audiotrack_outlined,
            size: 18,
            color: dim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? (_isVideo ? 'Video' : 'Audio'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [status, if (details.isNotEmpty) details].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.fieldLabel.copyWith(
                    fontSize: 8.5,
                    color: failed ? AppColors.rustPale : dim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A video's preview picture (or a dark placeholder when there is none),
/// with the button in the middle and size/length along the bottom. Tapping
/// anywhere does what the button does.
class _VideoPreview extends StatelessWidget {
  const _VideoPreview({
    required this.thumbnailPath,
    required this.button,
    required this.caption,
    required this.failed,
    this.onTap,
  });

  final String? thumbnailPath;
  final Widget button;
  final String caption;
  final bool failed;
  final VoidCallback? onTap;

  static const width = 220.0;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: const Color(0xFF1E2230),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 36,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailPath case final path?)
              Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: (width * dpr).round(),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
              )
            else
              placeholder,
            Center(child: button),
            if (caption.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 5),
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.fieldLabel.copyWith(
                        fontSize: 8.5,
                        color: failed ? AppColors.rustPale : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.color,
    required this.semantics,
    required this.child,
    this.onTap,
    this.onPicture = false,
  });

  final Color color;
  final String semantics;
  final Widget child;
  final VoidCallback? onTap;

  /// Drawn over a video preview: gets a dark backdrop to stay readable.
  final bool onPicture;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: semantics,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onPicture ? const Color(0x66000000) : null,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Center(child: child),
      ),
    ),
  );
}
