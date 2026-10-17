import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart'
    show ChatMenuButton;
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/wallpaper_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/chat/link_preview_card.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/official_badge.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The active-room id used while the official chat is on screen, so its
/// announcements don't also raise a banner.
const officialRoomId = 'serafim-official';

void openOfficialChat(BuildContext context) =>
    openOfficialChatWithNavigator(Navigator.of(context));

void openOfficialChatWithNavigator(NavigatorState navigator) {
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => const OfficialChatPage()),
  );
}

/// The official SERAFIM chat: announcements from the team, read-only for
/// everyone except administrators, who get a composer. Everything shown comes
/// from the server (and the copy of it saved on the phone).
class OfficialChatPage extends ConsumerStatefulWidget {
  const OfficialChatPage({super.key});

  @override
  ConsumerState<OfficialChatPage> createState() => _OfficialChatPageState();
}

class _OfficialChatPageState extends ConsumerState<OfficialChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final ActiveRoomNotifier _activeRoom;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _activeRoom = ref.read(activeRoomProvider.notifier);
    _scroll.addListener(_loadOlderNearTop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activeRoom.set(officialRoomId);
      ref.read(officialChatProvider.notifier).reload();
    });
  }

  @override
  void dispose() {
    // Not during the unmount itself: that would rebuild listeners while the
    // tree is locked.
    final notifier = _activeRoom;
    Future.microtask(() => notifier.clear(officialRoomId));
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _loadOlderNearTop() {
    // The list is reversed: the top is the far end.
    if (_scroll.position.extentAfter < 300) {
      ref.read(officialChatProvider.notifier).loadOlder();
    }
  }

  void _tell(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.rust : null,
        ),
      );
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    final error = await ref.read(officialChatProvider.notifier).post(text);
    if (!mounted) return;
    setState(() => _posting = false);
    if (error != null) {
      _tell(error);
    } else {
      _controller.clear();
    }
  }

  Future<void> _confirmDelete(Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Delete announcement?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          'It will be removed for everyone.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await ref.read(officialChatProvider.notifier).delete(a.id);
    if (error != null) _tell(error);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(officialChatProvider);
    final chat = async.value;

    // Looking at the chat counts as having read what is in it.
    final latest = chat?.latest;
    if (latest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(officialLastReadProvider.notifier)
              .markSeen(latest.createdAt);
        }
      });
    }

    Widget list;
    if (chat == null && async.hasError) {
      list = _Centered(
        text: humanError(async.error, fallback: "Couldn't load announcements."),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(officialChatProvider),
      );
    } else if (chat == null) {
      list = Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (chat.announcements.isEmpty) {
      list = const _Centered(
        text:
            'No announcements yet.\nNews from the SERAFIM team will appear here.',
      );
    } else {
      final items = chat.announcements;
      list = ListView.separated(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.all(14),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final a = items[i];
          return ChatBubble(
            who: 'SERAFIM · ${formatChatListTime(context, a.createdAt)}',
            message: a.content,
            side: ChatBubbleSide.incoming,
            footer: switch (firstLink(a.content)) {
              final uri? => LinkPreviewCard(uri: uri, outgoing: false),
              null => null,
            },
            onLongPress: chat.canPost ? () => _confirmDelete(a) : null,
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).pop(),
        titleWidget: Row(
          children: [
            const SerafimMark(size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'SERAFIM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const OfficialBadge(),
          ],
        ),
        trailing: const ChatMenuButton(roomId: officialRoomId),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ChatWallpaperView(
              wallpaper: ref.watch(roomWallpaperProvider(officialRoomId)),
            ),
          ),
          Column(
            children: [
              const _InfoStrip(),
              Expanded(child: list),
              if (chat?.canPost ?? false)
                ChatInputBar(
                  controller: _controller,
                  hintText: _posting
                      ? 'Posting…'
                      : 'Post an announcement to everyone…',
                  onSend: _posting ? null : _post,
                )
              else
                const _ReadOnlyFooter(),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.lineSoft, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_outlined, size: 16, color: AppColors.primaryPale),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Official news and announcements from the SERAFIM team.',
              style: AppTextStyles.smallDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyFooter extends StatelessWidget {
  const _ReadOnlyFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.paperRaised, AppColors.paperAlt],
        ),
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 13, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text(
              'Only SERAFIM can post in this chat',
              style: AppTextStyles.smallDim,
            ),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          color: AppColors.paper.withValues(alpha: 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!, style: AppTextStyles.linkText),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
