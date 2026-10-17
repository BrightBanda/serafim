import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/voice/voice_math.dart';

/// The mic button: hold to record, release to send; slide left to cancel,
/// slide up to lock (hands-free). While locked it becomes a send button.
class MicButton extends ConsumerStatefulWidget {
  const MicButton({super.key, required this.onRecorded, required this.onTell});

  /// A finished recording to send.
  final ValueChanged<RecordedVoice> onRecorded;

  /// Shows a short message (permission denied, too short…).
  final ValueChanged<String> onTell;

  @override
  ConsumerState<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends ConsumerState<MicButton> {
  VoiceRecorderController get _rec => ref.read(voiceRecorderProvider.notifier);

  Future<void> _start() async {
    final result = await _rec.start(onLimit: widget.onRecorded);
    switch (result) {
      case RecordStartResult.denied:
        widget.onTell(
          'Serafim needs microphone access to record voice messages. '
          "Allow it in your phone's settings (App info → Permissions).",
        );
      case RecordStartResult.failed:
        if (ref.read(voiceRecorderProvider).active) break;
        // Usually the permission prompt interrupted the hold.
        break;
      case RecordStartResult.started || RecordStartResult.busy:
        break;
    }
  }

  void _move(LongPressMoveUpdateDetails d) {
    final state = ref.read(voiceRecorderProvider);
    if (!state.active || state.locked) return;
    switch (recordGestureFor(d.offsetFromOrigin)) {
      case RecordGesture.cancel:
        _rec.cancel();
        widget.onTell('Voice message cancelled');
      case RecordGesture.lock:
        _rec.lock();
      case RecordGesture.none:
        break;
    }
  }

  Future<void> _release() async {
    final state = ref.read(voiceRecorderProvider);
    if (state.locked) return; // Hands-free: keeps recording.
    if (state.phase == RecordingPhase.starting) {
      await _rec.cancel();
      return;
    }
    if (!state.active) return;
    final voice = await _rec.finish();
    if (voice == null) {
      widget.onTell('Hold to record, release to send.');
    } else {
      widget.onRecorded(voice);
    }
  }

  Future<void> _sendLocked() async {
    final voice = await _rec.finish();
    if (voice != null) widget.onRecorded(voice);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceRecorderProvider);
    final recording = state.active;

    if (state.locked) {
      return _Square(
        semantics: 'Send voice message',
        filled: true,
        onTap: _sendLocked,
        icon: Icons.send_rounded,
      );
    }

    return Semantics(
      button: true,
      label: 'Hold to record a voice message',
      child: GestureDetector(
        onTap: () => widget.onTell('Hold to record, release to send.'),
        onLongPressStart: (_) => _start(),
        onLongPressMoveUpdate: _move,
        onLongPressEnd: (_) => _release(),
        // The hold was taken away (a system dialog, a call): keep it.
        onLongPressCancel: _rec.interrupt,
        child: AnimatedScale(
          scale: recording ? 1.25 : 1,
          duration: const Duration(milliseconds: 120),
          child: _Square(
            semantics: null,
            filled: recording,
            icon: Icons.mic_rounded,
          ),
        ),
      ),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({
    required this.icon,
    required this.filled,
    required this.semantics,
    this.onTap,
  });

  final IconData icon;
  final bool filled;
  final String? semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 44,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDeep],
              )
            : null,
        color: filled ? null : AppColors.paperAlt,
        border: Border.all(
          color: filled ? AppColors.line : AppColors.lineSoft,
          width: filled ? 2 : 1.5,
        ),
      ),
      child: Icon(
        icon,
        size: 20,
        color: filled ? Colors.white : AppColors.primaryPale,
      ),
    );
    if (semantics == null) return box;
    return Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(onTap: onTap, child: box),
    );
  }
}

/// Replaces the text field while recording: the timer and level, and either
/// the slide hints (holding) or cancel / pause / resume buttons (locked).
class RecordingStrip extends ConsumerWidget {
  const RecordingStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceRecorderProvider);
    final rec = ref.read(voiceRecorderProvider.notifier);
    final paused = state.phase == RecordingPhase.paused;
    final remaining = maxVoiceDuration - state.elapsed;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.rust, width: 1.5),
      ),
      child: Row(
        children: [
          _Dot(active: !paused, level: state.level),
          const SizedBox(width: 8),
          Text(
            formatVoiceDuration(state.elapsed),
            style: AppTextStyles.fieldLabel.copyWith(
              color: AppColors.text,
              fontSize: 11,
            ),
          ),
          if (remaining <= const Duration(seconds: 30)) ...[
            const SizedBox(width: 6),
            Text(
              '${remaining.inSeconds.clamp(0, 30)}s left',
              style: AppTextStyles.fieldLabel.copyWith(
                color: AppColors.rustPale,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: state.locked
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (paused)
                        Flexible(
                          child: Text(
                            'Paused',
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.smallDim,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Delete recording',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.rustPale,
                        ),
                        onPressed: rec.cancel,
                      ),
                      IconButton(
                        tooltip: paused
                            ? 'Resume recording'
                            : 'Pause recording',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          paused ? Icons.mic_rounded : Icons.pause_rounded,
                          size: 20,
                          color: AppColors.text,
                        ),
                        onPressed: paused ? rec.resume : rec.pause,
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.chevron_left,
                        size: 16,
                        color: AppColors.textDim,
                      ),
                      Flexible(
                        child: Text(
                          'Slide to cancel · up to lock',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.smallDim,
                        ),
                      ),
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: AppColors.textDim,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.level});

  final bool active;
  final int level;

  @override
  Widget build(BuildContext context) {
    final size = active ? 8 + level / 31 * 6 : 8.0;
    return SizedBox.square(
      dimension: 14,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.red.shade400 : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
