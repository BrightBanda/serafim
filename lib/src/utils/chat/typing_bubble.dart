import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// "Someone is typing": an incoming bubble in the app's boxy style with three
/// square dots that rise and fall in turn.
///
/// One controller drives all three dots and only the dots repaint
/// ([RepaintBoundary]), so it costs next to nothing while it is on screen. It
/// stands still when the phone has animations turned off.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key, required this.who});

  /// Who is typing: a name, or several for a group.
  final String who;

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1 bump for dot [i]: each dot lifts a little after the one before.
  double _lift(int i) {
    final t = (_c.value - i * 0.14) % 1.0;
    if (t >= 0.4) return 0;
    // Up and back down within the first 40% of the loop.
    return Curves.easeInOut.transform(t < 0.2 ? t / 0.2 : (0.4 - t) / 0.2);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.who} is typing',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.lineSoft, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.line,
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.who,
                style: AppTextStyles.fieldLabel.copyWith(
                  fontSize: 8,
                  color: AppColors.tealPale,
                ),
              ),
              const SizedBox(height: 5),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => SizedBox(
                    height: 16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Padding(
                            padding: EdgeInsets.only(bottom: 8 * _lift(i)),
                            child: Container(
                              width: 6,
                              height: 6,
                              color: AppColors.textDim.withValues(
                                alpha: 0.5 + 0.5 * _lift(i),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
