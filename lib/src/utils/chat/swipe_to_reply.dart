import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// Drag a message sideways (either direction) past a threshold to reply to
/// it. The bubble follows the finger, a reply icon fades in underneath, and it
/// springs back on release. Vertical scrolling is unaffected.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onReply;

  /// When false the gesture is ignored (e.g. for deleted messages).
  final bool enabled;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  // The drag only starts counting after Flutter's touch slop (~18 px), so the
  // finger really travels about 18 px more than this. A quick flick also
  // counts (see [_end]) — a short, fast swipe is how people actually do it.
  static const _trigger = 40.0;
  static const _maxDrag = 72.0;
  static const _flickSpeed = 600.0;
  static const _flickMin = 16.0;

  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Animation<double>? _backAnimation;

  double _dx = 0;
  bool _armed = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    if (!widget.enabled) return;
    _back.stop();
    setState(() {
      _dx = (_dx + details.delta.dx).clamp(-_maxDrag, _maxDrag);
      final nowArmed = _dx.abs() >= _trigger;
      if (nowArmed && !_armed) HapticFeedback.selectionClick();
      _armed = nowArmed;
    });
  }

  void _end(DragEndDetails details) {
    final speed = (details.primaryVelocity ?? 0).abs();
    if (!_armed && speed >= _flickSpeed && _dx.abs() >= _flickMin) {
      _armed = true;
    }
    _release(reply: true);
  }

  void _release({required bool reply}) {
    if (!widget.enabled) return;
    // A cancelled drag (the system took the gesture) must not send a reply.
    if (reply && _armed) widget.onReply();
    _armed = false;

    final from = _dx;
    _backAnimation = Tween<double>(begin: from, end: 0).animate(
      CurvedAnimation(parent: _back, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dx = _backAnimation!.value));
    _back
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dx.abs() / _trigger).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _release(reply: false),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_dx != 0)
            Positioned.fill(
              child: Align(
                // Sits on the side the bubble was dragged away from.
                alignment: _dx > 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * progress,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _armed
                            ? AppColors.primary
                            : AppColors.paperRaised,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.lineSoft,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.reply,
                        size: 16,
                        color: _armed ? Colors.white : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
