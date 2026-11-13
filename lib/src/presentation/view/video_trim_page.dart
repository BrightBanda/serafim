import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/trim_range.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/providers/video_trim_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:video_player/video_player.dart';

/// Lets the person choose which part of [file] to send. Returns the video to
/// send: [file] itself when all of it was kept, a new trimmed file otherwise
/// (its path differs; the caller deletes it after sending), or null if they
/// backed out.
Future<PickedChatFile?> chooseVideoPart(
  BuildContext context,
  PickedChatFile file,
) => Navigator.of(context).push<PickedChatFile>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => VideoTrimPage(file: file),
  ),
);

class VideoTrimPage extends ConsumerStatefulWidget {
  const VideoTrimPage({super.key, required this.file});

  final PickedChatFile file;

  @override
  ConsumerState<VideoTrimPage> createState() => _VideoTrimPageState();
}

class _VideoTrimPageState extends ConsumerState<VideoTrimPage> {
  late final VideoPlayerController _controller = VideoPlayerController.file(
    File(widget.file.path),
  );
  TrimRange? _range;
  bool _failed = false;
  bool _dragging = false;
  bool _trimming = false;

  @override
  void initState() {
    super.initState();
    _controller.initialize().then(
      (_) {
        if (!mounted) return;
        setState(() => _range = TrimRange.whole(_controller.value.duration));
        _controller
          ..addListener(_keepInside)
          ..play();
      },
      onError: (_) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_keepInside);
    _controller.dispose();
    super.dispose();
  }

  /// Plays the chosen part over and over.
  void _keepInside() {
    final range = _range;
    if (range == null || _dragging || !_controller.value.isPlaying) return;
    if (_controller.value.position >= range.end) {
      _controller.seekTo(range.start);
    }
  }

  void _toggle() {
    if (!_controller.value.isInitialized || _trimming) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _onDrag(RangeValues values) {
    final range = _range;
    if (range == null) return;
    final start = Duration(milliseconds: values.start.round());
    final end = Duration(milliseconds: values.end.round());
    // Whichever handle moved further is the one being dragged.
    final startMoved = (start - range.start).abs() >= (end - range.end).abs();
    final next = startMoved ? range.withStart(start) : range.withEnd(end);
    setState(() => _range = next);
    // The picture follows the handle, so you can see the exact frame.
    _controller.seekTo(
      startMoved
          ? next.start
          : next.end - const Duration(milliseconds: 300) > next.start
          ? next.end - const Duration(milliseconds: 300)
          : next.start,
    );
  }

  Future<void> _send() async {
    final range = _range;
    if (range == null || _trimming) return;
    if (range.isWhole) {
      Navigator.of(context).pop(widget.file);
      return;
    }
    setState(() => _trimming = true);
    _controller.pause();
    final trimmer = ref.read(videoTrimServiceProvider);
    try {
      final path = await trimmer.trim(
        path: widget.file.path,
        start: range.start,
        end: range.end,
      );
      final size = await File(path).length();
      if (!mounted) {
        File(path).delete().ignore();
        return;
      }
      Navigator.of(context).pop(
        PickedChatFile(
          path: path,
          name: _trimmedName(widget.file.name),
          size: size,
          kind: ChatFileKind.video,
          durationMs: range.length.inMilliseconds,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _trimming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanError(error, fallback: "Couldn't trim that video."),
          ),
        ),
      );
    }
  }

  /// The trimmed copy is always an MP4, whatever the original was.
  static String _trimmedName(String name) {
    final dot = name.lastIndexOf('.');
    return '${dot > 0 ? name.substring(0, dot) : name}.mp4';
  }

  Future<void> _close() async {
    if (_trimming) await ref.read(videoTrimServiceProvider).cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_trimming,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _failed
              ? Center(
                  child: Text(
                    "This video can't be opened on this phone.",
                    style: AppTextStyles.body.copyWith(color: Colors.white70),
                  ),
                )
              : Column(
                  children: [
                    _header(),
                    Expanded(child: _preview()),
                    _controls(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('trim-close'),
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Close',
          onPressed: _close,
        ),
        Text(
          'Choose the part to send',
          style: AppTextStyles.body.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _preview() => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: _controller,
    builder: (context, value, _) {
      if (!value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Center(
          child: AspectRatio(
            aspectRatio: value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller),
                if (!value.isPlaying && !_trimming)
                  const Icon(
                    Icons.play_circle_outline,
                    color: Colors.white70,
                    size: 72,
                  ),
                if (_trimming)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _controls() {
    final range = _range;
    if (range == null) return const SizedBox(height: 180);
    final estimate = range.estimatedBytes(widget.file.size);
    final tooBig = estimate > maxChatFileBytes;
    final dim = AppTextStyles.smallDim;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.lineSoft,
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 11,
              ),
              thumbColor: AppColors.primaryPale,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            child: RangeSlider(
              key: const ValueKey('trim-slider'),
              min: 0,
              max: range.total.inMilliseconds.toDouble(),
              values: RangeValues(
                range.start.inMilliseconds.toDouble(),
                range.end.inMilliseconds.toDouble(),
              ),
              onChangeStart: (_) {
                _dragging = true;
                _controller.pause();
              },
              onChanged: _trimming ? null : _onDrag,
              onChangeEnd: (_) {
                _dragging = false;
                _controller
                  ..seekTo(range.start)
                  ..play();
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatClock(range.start), style: dim),
              Text(
                '${formatClock(range.length)} · '
                '${tooBig ? 'too big, ' : '≈ '}${formatFileSize(estimate)}',
                key: const ValueKey('trim-summary'),
                style: dim.copyWith(color: tooBig ? AppColors.rust : null),
              ),
              Text(formatClock(range.end), style: dim),
            ],
          ),
          const SizedBox(height: 12),
          SerafimButton(
            label: _trimming
                ? 'TRIMMING…'
                : range.isWhole
                ? 'SEND'
                : 'TRIM AND SEND',
            onPressed: _trimming || tooBig ? null : _send,
          ),
        ],
      ),
    );
  }
}
