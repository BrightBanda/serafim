import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/services/chat_features_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/presentation/view/nicknames_page.dart';
import 'package:serafim/src/providers/chat_features_providers.dart';
import 'package:serafim/src/providers/nickname_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Chat menu → Chat features: options for this one conversation, shared by
/// everyone in it. In a 1:1 chat either of you may change them; in a group,
/// only the owner and admins.
class ChatFeaturesPage extends ConsumerStatefulWidget {
  const ChatFeaturesPage({
    super.key,
    required this.chat,
    required this.name,
    this.nicknameFriendId,
  });

  final ChatRef chat;

  /// Set in a 1:1 chat with a friend: shows the Nicknames entry.
  final String? nicknameFriendId;

  /// The other person's (or the group's) name.
  final String name;

  @override
  ConsumerState<ChatFeaturesPage> createState() => _ChatFeaturesPageState();
}

class _ChatFeaturesPageState extends ConsumerState<ChatFeaturesPage> {
  @override
  void initState() {
    super.initState();
    // The saved copy shows at once; this brings it up to date.
    unawaited(
      ref
          .read(chatFeaturesControllerProvider.notifier)
          .load(widget.chat)
          .catchError((Object _) {}),
    );
  }

  Future<void> _setShowDeleted(bool show) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(chatFeaturesControllerProvider.notifier)
          .setHideDeleted(widget.chat, !show);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAccountIdProvider);
    if (me == null) return const SizedBox.shrink();
    final features = ref.watch(
      chatFeaturesProvider(roomIdOfChat(me, widget.chat)),
    );
    final group = widget.chat.isGroup;
    final by = features.updatedBy;
    final byName = by == null
        ? null
        : by == me
        ? 'you'
        : ref.watch(knownPersonProvider(by))?.displayName ??
              (group ? 'an admin' : widget.name);

    return SettingsScaffold(
      title: 'CHAT FEATURES',
      children: [
        SettingsNote(
          group
              ? 'These apply to everyone in ${widget.name}. Only the owner '
                    'and admins can change them.'
              : 'These apply to you and ${widget.name}. Either of you can '
                    'change them.',
        ),
        SettingsSwitchRow(
          key: const ValueKey('chat-feature-show-deleted'),
          title: 'Show deleted messages',
          subtitle: features.hideDeleted
              ? 'Off: deleted messages disappear without a trace.'
              : 'On: "This message was deleted" stays where a message was.',
          value: !features.hideDeleted,
          onChanged: features.canEdit ? _setShowDeleted : null,
        ),
        if (byName != null)
          SettingsNote(
            'Last changed by $byName.',
            key: const ValueKey('chat-features-changed-by'),
          ),
        if (widget.nicknameFriendId case final friend?) ...[
          const SettingsSectionLabel('Nicknames'),
          _NicknamesRow(friendId: friend, friendName: widget.name),
        ],
      ],
    );
  }
}

/// What you call your friend and what they call you, opening the Nicknames
/// page.
class _NicknamesRow extends ConsumerWidget {
  const _NicknamesRow({required this.friendId, required this.friendName});

  final String friendId;
  final String friendName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final given = ref.watch(nicknameForProvider(friendId));
    final received = ref.watch(nicknameFromProvider(friendId));
    final parts = [
      given == null ? 'No nickname for $friendName' : 'You call them "$given"',
      if (received != null) 'they call you "$received"',
    ];
    return Material(
      color: AppColors.paperAlt,
      shape: Border.all(color: AppColors.lineSoft, width: 1.5),
      child: ListTile(
        key: const ValueKey('chat-features-nicknames'),
        leading: Icon(Icons.badge_outlined, color: AppColors.primaryPale),
        title: Text(
          'Nicknames',
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.text,
          ),
        ),
        subtitle: Text(parts.join(' · '), style: AppTextStyles.smallDim),
        trailing: Icon(Icons.chevron_right, color: AppColors.textDim),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                NicknamesPage(friendId: friendId, friendName: friendName),
          ),
        ),
      ),
    );
  }
}
