import 'package:flutter/material.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';

/// Opens a group's conversation.
void openGroupChat(BuildContext context, GroupSummary group) =>
    openGroupChatWithNavigator(Navigator.of(context), group);

/// Same, from code with a navigator but no BuildContext (banners, pushes).
void openGroupChatWithNavigator(NavigatorState navigator, GroupSummary group) {
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ChatThreadPage(
        contactName: group.name,
        recipientId: group.id,
        groupId: group.id,
        profilePic: group.photoUrl,
        isGroup: true,
      ),
    ),
  );
}
