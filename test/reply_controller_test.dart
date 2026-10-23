import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/utils/chat/reply_controller.dart';
import 'package:serafim/src/utils/settled_sheet.dart';

LocalMessage _msg({
  MessageStatus status = MessageStatus.sent,
  bool deleted = false,
}) => LocalMessage()
  ..messageId = 'm1'
  ..status = status
  ..isDeleted = deleted;

class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final focus = FocusNode();
  late final reply = ReplyController(focusNode: focus);
  final controller = TextEditingController();

  @override
  void dispose() {
    reply.dispose();
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final action = await showSettledSheet<String>(
                  context: context,
                  builder: (ctx) => ListTile(
                    title: const Text('Reply'),
                    onTap: () => Navigator.pop(ctx, 'reply'),
                  ),
                );
                if (action == 'reply') reply.start(_msg());
              },
              child: const Text('hold'),
            ),
          ),
          TextField(controller: controller, focusNode: focus),
        ],
      ),
    ),
  );
}

void main() {
  group('who can be replied to', () {
    test('sent messages yes; deleted, sending and failed no', () {
      expect(ReplyController.canReplyTo(_msg()), isTrue);
      expect(ReplyController.canReplyTo(_msg(deleted: true)), isFalse);
      expect(
        ReplyController.canReplyTo(_msg(status: MessageStatus.sending)),
        isFalse,
      );
      expect(
        ReplyController.canReplyTo(_msg(status: MessageStatus.failed)),
        isFalse,
      );
    });

    test('start refuses a message it cannot reply to and changes nothing', () {
      final c = ReplyController(focusNode: FocusNode());
      addTearDown(c.dispose);
      expect(c.start(_msg(deleted: true)), isFalse);
      expect(c.value, isNull);
      expect(c.start(_msg()), isTrue);
      expect(c.value?.messageId, 'm1');
      c.clear();
      expect(c.value, isNull);
    });
  });

  testWidgets('starting a reply focuses the message field', (tester) async {
    await tester.pumpWidget(const _Page());
    final page = tester.state<_PageState>(find.byType(_Page));
    expect(page.focus.hasFocus, isFalse);

    page.reply.start(_msg());
    await tester.pump();
    expect(page.focus.hasFocus, isTrue);
    expect(page.reply.value, isNotNull);
  });

  testWidgets('a sheet answers only when it is completely gone', (
    tester,
  ) async {
    await tester.pumpWidget(const _Page());
    final page = tester.state<_PageState>(find.byType(_Page));

    await tester.tap(find.text('hold'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);

    await tester.tap(find.text('Reply'));
    // Popped, but still sliding away: the reply must not have started yet.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Reply'), findsOneWidget, reason: 'sheet still animating');
    expect(page.reply.value, isNull, reason: 'waits for the sheet to be gone');

    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsNothing);
    expect(page.reply.value, isNotNull);
    expect(page.focus.hasFocus, isTrue, reason: 'keyboard field has focus');
  });
}
