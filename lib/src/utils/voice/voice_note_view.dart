import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/voice/voice_math.dart';

/// The inside of a voice-note bubble: play/pause, a waveform you can tap or
/// drag to seek, the time, and a 1×/1.5×/2× speed button. While sending it
/// shows upload progress; if sending failed, a retry button.
class VoiceNoteView extends ConsumerWidget {
  const VoiceNoteView({
    super.key,
    required this.messageId,
    required this.outgoing,
    required this.path,
    required this.durationMs,
    required this.waveform,
    this.failed = false,
    this.onRetry,
    this.onDownload,
  });

  final String messageId;
  final bool outgoing;

  /// Local audio file; null until a received note has downloaded.
  final String? path;
  final int durationMs;
  final List<int> waveform;
  final bool failed;
  final VoidCallback? onRetry;
  final Future<bool> Function()? onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(voicePlayerProvider);
    final upload = ref.watch(
      voiceUploadProgressProvider.select((m) => m[messageId]),
    );
    final isCurrent = playback.messageId == messageId;
    final total = isCurrent && playback.duration > Duration.zero
        ? playback.duration
        : Duration(milliseconds: durationMs);
    final position = isCurrent ? playback.position : Duration.zero;
    final fraction = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    final fg = outgoing ? Colors.white : AppColors.text;
    final dim = outgoing ? const Color(0xFFDBE4FB) : AppColors.textDim;
    final player = ref.read(voicePlayerProvider.notifier);

    Widget button;
    if (upload != null) {
      button = _Round(
        color: fg,
        semantics: 'Sending voice message, ${(upload * 100).round()} percent',
        child: CircularProgressIndicator(
          value: upload <= 0 ? null : upload,
          strokeWidth: 2.5,
          color: fg,
        ),
      );
    } else if (failed) {
      button = _Round(
        color: AppColors.rustPale,
        semantics: 'Sending failed. Retry',
        onTap: onRetry,
        child: Icon(Icons.refresh, color: AppColors.rustPale, size: 20),
      );
    } else if (path == null) {
      button = _DownloadButton(color: fg, onDownload: onDownload);
    } else {
      final playing = isCurrent && playback.playing;
      button = _Round(
        color: fg,
        semantics: playing ? 'Pause voice message' : 'Play voice message',
        onTap: () => player.toggle(messageId, path!, durationMs: durationMs),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: fg,
          size: 24,
        ),
      );
    }

    return SizedBox(
      width: 230,
      child: Row(
        children: [
          button,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    void seekTo(double dx) {
                      if (!isCurrent) return;
                      player.seek(messageId, dx / box.maxWidth);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => seekTo(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
                      child: SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: WaveformPainter(
                            levels: waveform,
                            progress: fraction,
                            played: fg,
                            unplayed: dim.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      isCurrent
                          ? '${formatVoiceDuration(position)} / ${formatVoiceDuration(total)}'
                          : formatVoiceDuration(total),
                      style: AppTextStyles.fieldLabel.copyWith(
                        fontSize: 8.5,
                        color: dim,
                      ),
                    ),
                    const Spacer(),
                    if (path != null && upload == null && !failed)
                      Semantics(
                        button: true,
                        label: 'Playback speed ${_speed(playback.speed)}',
                        child: GestureDetector(
                          onTap: player.cycleSpeed,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: dim, width: 1),
                            ),
                            child: Text(
                              _speed(playback.speed),
                              style: AppTextStyles.fieldLabel.copyWith(
                                fontSize: 8.5,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _speed(double s) =>
      s == s.roundToDouble() ? '${s.toInt()}×' : '$s×';
}

class _Round extends StatelessWidget {
  const _Round({
    required this.child,
    required this.color,
    required this.semantics,
    this.onTap,
  });

  final Widget child;
  final Color color;
  final String semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semantics,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// For a received note whose audio isn't on the device yet (automatic
/// download failed, e.g. offline).
class _DownloadButton extends StatefulWidget {
  const _DownloadButton({required this.color, required this.onDownload});

  final Color color;
  final Future<bool> Function()? onDownload;

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _busy = false;

  Future<void> _go() async {
    final download = widget.onDownload;
    if (download == null || _busy) return;
    setState(() => _busy = true);
    final ok = await download();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't download the voice message. Try again."),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Round(
      color: widget.color,
      semantics: 'Download voice message',
      onTap: _go,
      child: _busy
          ? CircularProgressIndicator(strokeWidth: 2.5, color: widget.color)
          : Icon(Icons.download_rounded, color: widget.color, size: 20),
    );
  }
}

/// Bars of [levels] (0–31), the first [progress] fraction drawn as played.
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.levels,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  final List<int> levels;
  final double progress;
  final Color played;
  final Color unplayed;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = levels.isEmpty ? List.filled(waveformBars, 4) : levels;
    final step = size.width / bars.length;
    final barWidth = (step * 0.6).clamp(1.5, 4.0);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars.length; i++) {
      final h = (3 + (bars[i] / 31) * (size.height - 3)).clamp(
        3.0,
        size.height,
      );
      final x = i * step + step / 2;
      paint
        ..color = (i + 0.5) / bars.length <= progress ? played : unplayed
        ..strokeWidth = barWidth;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.progress != progress ||
      old.levels != levels ||
      old.played != played ||
      old.unplayed != unplayed;
}
