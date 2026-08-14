import 'package:serafim/src/utils/chat/chat_bubble.dart';

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
