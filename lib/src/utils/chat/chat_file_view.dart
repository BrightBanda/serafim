import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/voice/voice_math.dart';

/// The inside of a video or audio-file bubble: what it is (name, size,
/// length) and one round button for whatever comes next — sending progress,
/// retry, download (with progress), play.
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

    final fg = outgoing ? Colors.white : AppColors.text;
    final dim = outgoing ? const Color(0xFFDBE4FB) : AppColors.textDim;
    final what = _isVideo ? 'video' : 'audio';

    final Widget button;
    final String status;
    if (transfer != null) {
      final percent = (transfer.progress * 100).round();
      final sending = transfer.direction == FileTransferDirection.upload;
      status = '${sending ? 'Sending' : 'Downloading'} $percent%';
      button = _Round(
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
      button = _Round(
        color: AppColors.rustPale,
        semantics: 'Sending failed. Retry',
        onTap: onRetry,
        child: Icon(Icons.refresh, color: AppColors.rustPale, size: 20),
      );
    } else if (path == null) {
      status = message.mediaRemoteId == null
          ? 'Not available'
          : 'Tap to download';
      button = _Round(
        color: fg,
        semantics: 'Download $what',
        onTap: message.mediaRemoteId == null ? null : onDownload,
        child: Icon(Icons.download_rounded, color: fg, size: 22),
      );
    } else if (_isVideo) {
      status = message.status == MessageStatus.sending ? 'Sending…' : 'Video';
      button = _Round(
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

class _Round extends StatelessWidget {
  const _Round({
    required this.color,
    required this.semantics,
    required this.child,
    this.onTap,
  });

  final Color color;
  final String semantics;
  final Widget child;
  final VoidCallback? onTap;

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
          border: Border.all(color: color, width: 1.5),
        ),
        child: Center(child: child),
      ),
    ),
  );
}
