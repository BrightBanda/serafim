import 'package:flutter/material.dart';
import 'package:serafim/src/data/models/moment.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// What the ring round a picture says about someone's moments.
enum MomentRingState {
  /// Nothing showing, or none you may see: no ring.
  none,

  /// Something you haven't looked at yet: a bright coloured ring.
  unseen,

  /// You have looked at all of it: a quiet ring.
  seen;

  static MomentRingState of(MomentRing? ring) => ring == null
      ? none
      : ring.allSeen
      ? seen
      : unseen;
}

/// How much room the ring takes round a picture: its line, then a small gap.
const double momentRingLine = 2.5;
const double momentRingGap = 2;
const double momentRingSpace = 2 * (momentRingLine + momentRingGap);

/// A coloured circle round [child] (which should be [size] minus
/// [momentRingSpace] across). The Halo, if lit, sits inside the child.
class MomentRingFrame extends StatelessWidget {
  const MomentRingFrame({
    super.key,
    required this.size,
    required this.state,
    required this.child,
  });

  final double size;
  final MomentRingState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (state == MomentRingState.none) return child;
    final unseen = state == MomentRingState.unseen;
    return Semantics(
      label: unseen ? 'Has a new moment' : 'Has a moment',
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(momentRingLine),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: unseen
              ? SweepGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.rust,
                    const Color(0xFFFFB300),
                    AppColors.primary,
                  ],
                )
              : null,
          color: unseen ? null : AppColors.lineSoft,
        ),
        child: Container(
          padding: const EdgeInsets.all(momentRingGap),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The gap between the ring and the picture.
            color: AppColors.paper,
          ),
          child: child,
        ),
      ),
    );
  }
}
