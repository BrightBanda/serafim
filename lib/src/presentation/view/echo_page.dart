import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/utils/serafim_loader.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/echo.dart';
import 'package:serafim/src/providers/echo_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// What an Echo notification opens: who sent it, what they said and what
/// you have in common, with Start chat or Not now, so nobody starts a chat
/// by accident.
class EchoPage extends ConsumerStatefulWidget {
  const EchoPage({super.key, required this.fromUserId});

  /// The sender: the card shows the latest Echo they sent you.
  final String fromUserId;

  @override
  ConsumerState<EchoPage> createState() => _EchoPageState();
}

class _EchoPageState extends ConsumerState<EchoPage> {
  bool _busy = false;

  Future<void> _start(Echo echo) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(echoActionsProvider).respond(echo.id);
      navigator.pop();
      openChatWithNavigator(navigator, echo.user);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
      ref.invalidate(echoFromProvider(widget.fromUserId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hide(Echo echo) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(echoActionsProvider).hide(echo.user.id);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text("You won't get Echos from ${echo.user.displayName}."),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final echo = ref.watch(echoFromProvider(widget.fromUserId));
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'ECHO',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: echo.when(
          loading: () => const Center(child: SerafimLoader()),
          error: (e, _) => _Message(text: humanError(e)),
          data: (e) => _card(e),
        ),
      ),
    );
  }

  Widget _card(Echo echo) {
    final now = DateTime.now().toUtc();
    final pic = echo.user.profilePic;
    final ended = echo.minutesLeft(now) == 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Center(
          child: AvatarThumb(
            size: 72,
            imageProvider: pic != null && pic.isNotEmpty
                ? CachedNetworkImageProvider(pic)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          echo.user.displayName,
          textAlign: TextAlign.center,
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        Text(
          echo.isFriend ? 'Your friend' : '@${echo.user.username}',
          textAlign: TextAlign.center,
          style: AppTextStyles.smallDim,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Text(
            echo.text,
            key: const ValueKey('echo-message'),
            textAlign: TextAlign.center,
            style: AppTextStyles.fieldInput.copyWith(fontSize: 17),
          ),
        ),
        const SizedBox(height: 12),
        if (echo.sharedInterests.isNotEmpty)
          Text(
            'You both like ${echo.sharedInterests.join(', ')}',
            textAlign: TextAlign.center,
            style: AppTextStyles.smallDim.copyWith(
              color: AppColors.primaryPale,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          ended
              ? 'This Echo has ended.'
              : 'Open for ${echo.minutesLeft(now)} more min',
          textAlign: TextAlign.center,
          style: AppTextStyles.smallDim,
        ),
        const SizedBox(height: 24),
        if (!ended)
          SerafimButton(
            key: const ValueKey('echo-start-chat'),
            label: _busy
                ? 'OPENING…'
                : echo.responded
                ? 'OPEN CHAT'
                : 'START CHAT',
            onPressed: _busy ? null : () => _start(echo),
          ),
        const SizedBox(height: 8),
        SerafimButton(
          key: const ValueKey('echo-not-now'),
          label: ended ? 'CLOSE' : 'NOT NOW',
          isPrimary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 16),
        TextButton(
          key: const ValueKey('echo-hide'),
          onPressed: () => _hide(echo),
          child: Text(
            "Don't get Echos from ${echo.user.displayName}",
            style: AppTextStyles.linkText,
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, style: AppTextStyles.body, textAlign: TextAlign.center),
    ),
  );
}
