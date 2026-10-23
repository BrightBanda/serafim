import 'package:flutter/material.dart';

/// Shows a modal bottom sheet and returns its result only once the sheet has
/// **completely gone**: closing animation finished, its overlay removed.
///
/// Why this exists: [showModalBottomSheet] completes its future the moment
/// the sheet is popped, while the sheet is still sliding away. For that whole
/// animation the sheet's own focus scope is alive and owns focus, so anything
/// done in reaction to the result — opening the keyboard for a reply, pushing
/// a page, showing a dialog — races with the sheet tearing itself down. Flutter
/// gives the exact signal for "really gone" ([TransitionRoute.completed]);
/// this waits for it, so the caller never needs a timer.
Future<T?> showSettledSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<T>(
    builder: builder,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    isScrollControlled: isScrollControlled,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    backgroundColor: backgroundColor,
    shape: shape,
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
  );
  navigator.push(route);
  return route.completed;
}
