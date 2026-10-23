import 'dart:async';

/// Tells the other side that you are typing — gently.
///
/// What it sends, and when:
///  * the first keystroke: "typing" at once;
///  * while you keep typing: "typing" again only every [repeatEvery], not on
///    every key (the other side treats it as true for ~6 s);
///  * when you stop for [idleAfter], clear the box, or send: "stopped", once.
/// So a long message costs a handful of tiny frames, not one per character.
class TypingBroadcaster {
  TypingBroadcaster({
    required this.send,
    this.repeatEvery = const Duration(seconds: 3),
    this.idleAfter = const Duration(seconds: 4),
  });

  /// Called with true ("typing") or false ("stopped").
  final void Function(bool typing) send;

  final Duration repeatEvery;
  final Duration idleAfter;

  bool _active = false;
  bool _coolingDown = false;
  Timer? _cooldown;
  Timer? _idle;

  /// Call on every change of the message box's text.
  void textChanged(String text) {
    if (text.trim().isEmpty) {
      stop();
      return;
    }
    if (!_coolingDown) {
      _active = true;
      send(true);
      _coolingDown = true;
      _cooldown = Timer(repeatEvery, () => _coolingDown = false);
    }
    _idle?.cancel();
    _idle = Timer(idleAfter, stop);
  }

  /// You stopped (or sent, or left). Says so once, and only if it said
  /// "typing" before.
  void stop() {
    _idle?.cancel();
    _cooldown?.cancel();
    _coolingDown = false;
    if (_active) {
      _active = false;
      send(false);
    }
  }

  void dispose() => stop();
}
