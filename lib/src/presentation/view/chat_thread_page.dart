import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// A single message. Plain data holder — no send/receive logic here.
class ChatMessage {
  const ChatMessage({
    required this.who,
    required this.text,
    required this.side,
  });

  final String who;
  final String text;
  final ChatBubbleSide side;
}

/// Chat thread screen. Reuses SerafimTopBar (with its new `leading`
/// slot for the small avatar), SerafimAvatarThumb, SerafimChatBubble,
/// and SerafimChatInputBar.
///
/// UI only — [onSend] fires with the current text field contents;
/// actually sending/appending the message is the caller's job.
class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.contactName,
    this.isGroup = false,
    this.messages = _sampleMessages,
    this.onBack,
    this.onSend,
  });

  final String contactName;
  final bool isGroup;
  final List<ChatMessage> messages;
  final VoidCallback? onBack;
  final ValueChanged<String>? onSend;

  static const _sampleMessages = [
    ChatMessage(
      who: 'Serafim · 22:05',
      text:
          'I sense a disturbance in the localized field near Sector 76. Have you checked the telemetry array?',
      side: ChatBubbleSide.incoming,
    ),
    ChatMessage(
      who: 'You · 22:07',
      text:
          "Yeah, recalibrated last cycle. Might be residual energy from the nebula storm — running a diagnostic sweep now.",
      side: ChatBubbleSide.outgoing,
    ),
    ChatMessage(
      who: 'Serafim · 22:08',
      text:
          "Keep your proximity sensors active — I don't want us caught off guard again.",
      side: ChatBubbleSide.incoming,
    ),
    ChatMessage(
      who: 'You · 22:09',
      text: "Copy that. Sweep's clean so far, will report if anything spikes.",
      side: ChatBubbleSide.outgoing,
    ),
  ];

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        onBack: widget.onBack,
        titleFontSize: 15,
        title: widget.contactName,
        trailing: AvatarThumb(size: 28, isGroup: widget.isGroup),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: _StatusLine(),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: widget.messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final m = widget.messages[index];
                  return ChatBubble(who: m.who, message: m.text, side: m.side);
                },
              ),
            ),
            ChatInputBar(
              controller: _controller,
              onSend: () => widget.onSend?.call(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft, width: 1)),
      ),
      child: const Text(
        'COMM-LINK ESTABLISHED · 22:04 STARDATE',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 9,
          color: AppColors.textDim,
        ),
      ),
    );
  }
}
