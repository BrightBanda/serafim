import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/chat/swipe_to_reply.dart';

/// A cut-down chat: a list of swipeable messages over the real input bar,
/// wired the way ChatThreadPage wires reply (set the preview, then focus the
/// field).
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final focus = FocusNode();
  final controller = TextEditingController();
  String? replyingTo;
  int replies = 0;

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  void reply(String who) {
    replies++;
    setState(() => replyingTo = who);
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: ListView.separated(
                reverse: true,
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => SwipeToReply(
                  onReply: () => reply('m$i'),
                  child: SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: Text('m$i'),
                  ),
                ),
              ),
            ),
            ChatInputBar(
              controller: controller,
              focusNode: focus,
              replyPreview: replyingTo == null
                  ? null
                  : (
                      author: replyingTo!,
                      snippet: 'quoted',
                      onCancel: () => setState(() => replyingTo = null),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('swiping to reply keeps working, and keeps the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    for (var round = 1; round <= 3; round++) {
      await tester.drag(find.text('m1'), const Offset(-140, 0));
      await tester.pumpAndSettle();
      expect(state.replies, round, reason: 'swipe $round should reply');
      expect(
        state.focus.hasFocus,
        isTrue,
        reason: 'keyboard after swipe $round',
      );
    }
  });

  testWidgets('starting and cancelling a reply never drops the field', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(state.focus.hasFocus, isTrue);

    // The reply bar appearing must not rebuild the text field under the
    // cursor: same element, same focus.
    final before = tester.element(find.byType(TextField));
    state.reply('m0');
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(TextField)), same(before));
    expect(state.focus.hasFocus, isTrue);

    state.setState(() => state.replyingTo = null);
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(TextField)), same(before));
  });
}
