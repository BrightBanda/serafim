import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';

/// Which message the person is replying to, and getting the keyboard up for
/// it. The one place that knows how replying works, so the chat page only
/// says *start*, *clear*, or *what is the reply to*.
///
/// Design, in the way messaging apps do it:
///  * the reply target is plain state ([value]) that the input bar listens to;
///    nothing else in the page rebuilds when it changes;
///  * starting a reply sets the target and asks the same, long-lived text
///    field for focus. The field is never rebuilt (see `ChatInputBar`), so the
///    request cannot be lost to it being replaced;
///  * if the field kept focus after the keyboard was dismissed (Back button),
///    asking for focus does nothing — so the platform is also told to show
///    the keyboard.
/// Callers that start a reply from something that is closing (a bottom sheet)
/// should wait for it to be fully gone first: see `showSettledSheet`.
class ReplyController extends ValueNotifier<LocalMessage?> {
  ReplyController({required this.focusNode}) : super(null);

  /// The message field's focus node.
  final FocusNode focusNode;

  /// A message can be replied to once the server has it, and until it is
  /// deleted.
  static bool canReplyTo(LocalMessage m) =>
      !m.isDeleted &&
      m.status != MessageStatus.sending &&
      m.status != MessageStatus.failed;

  /// Starts replying to [message] and brings the keyboard up. Returns false
  /// (changing nothing) when that message cannot be replied to.
  bool start(LocalMessage message) {
    if (!canReplyTo(message)) return false;
    value = message;
    showKeyboard();
    return true;
  }

  /// Drops the reply (cancelled, or sent).
  void clear() {
    if (value != null) value = null;
  }

  /// Focuses the message field and makes sure the keyboard is showing.
  void showKeyboard() {
    focusNode.requestFocus();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!focusNode.hasFocus) return;
      try {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } catch (_) {
        // No platform keyboard (tests, desktop): focus is all there is.
      }
    });
  }
}
