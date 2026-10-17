import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/providers/notification_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// Opens the notifications page from code with no BuildContext (a banner).
void openNotificationsWithNavigator(NavigatorState navigator) {
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
  );
}

/// Friend requests, accepted requests and new followers, newest first.
/// Unread ones are highlighted; swipe one sideways to remove it.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  void _tell(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.rust),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final controller = ref.read(notificationsProvider.notifier);
    final unread = ref.watch(unreadNotificationCountProvider);

    Future<void> dismiss(AppNotification n) async {
      final error = await controller.dismiss(n.id);
      if (error != null && context.mounted) _tell(context, error);
    }

    Future<void> open(AppNotification n) async {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfilePage(userId: n.actor.id),
        ),
      );
      final error = await controller.markRead(n.id);
      if (error != null && context.mounted) _tell(context, error);
    }

    Widget scrollable(List<Widget> children) => RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.paperRaised,
      onRefresh: controller.reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: children,
      ),
    );

    final list = async.value;
    Widget body;
    if (list == null && async.hasError) {
      body = scrollable([
        const SizedBox(height: 80),
        _Message(
          icon: Icons.cloud_off_outlined,
          text: humanError(
            async.error,
            fallback: "Couldn't load your notifications.",
          ),
          actionLabel: 'Try again',
          onAction: controller.reload,
        ),
      ]);
    } else if (list == null) {
      body = Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (list.isEmpty) {
      body = scrollable([
        const SizedBox(height: 80),
        const _Message(
          icon: Icons.notifications_none_rounded,
          text:
              "You're all caught up.\nFriend requests and new followers "
              'will show up here.',
        ),
      ]);
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.paperRaised,
        onRefresh: controller.reload,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          itemCount: list.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Text(
                unread > 0 ? 'NEW · $unread UNREAD' : 'EARLIER',
                style: AppTextStyles.eyebrow,
              );
            }
            final n = list[i - 1];
            return Dismissible(
              key: ValueKey('notification-${n.id}'),
              background: const _SwipeBackground(
                alignment: Alignment.centerLeft,
              ),
              secondaryBackground: const _SwipeBackground(
                alignment: Alignment.centerRight,
              ),
              onDismissed: (_) => dismiss(n),
              child: _NotificationCard(notification: n, onTap: () => open(n)),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'NOTIFICATIONS',
        onBack: () => Navigator.of(context).pop(),
        trailing: unread == 0
            ? null
            : TextButton(
                onPressed: () async {
                  final error = await controller.markAllRead();
                  if (error != null && context.mounted) _tell(context, error);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  'Mark all read',
                  style: AppTextStyles.linkText.copyWith(fontSize: 11),
                ),
              ),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon => switch (notification.kind) {
    NotificationKind.friendRequest => Icons.person_add_alt_1_rounded,
    NotificationKind.friendAccepted => Icons.people_alt_rounded,
    NotificationKind.newFollower => Icons.favorite_rounded,
    NotificationKind.unknown => Icons.notifications_rounded,
  };

  Color get _accent => switch (notification.kind) {
    NotificationKind.friendRequest => AppColors.primary,
    NotificationKind.friendAccepted => AppColors.teal,
    NotificationKind.newFollower => AppColors.rust,
    NotificationKind.unknown => AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.isRead;
    final accent = _accent;

    // Unread: a tinted, raised card with an accent stripe and dot. Read: the
    // plain surface with dimmer text.
    final surface = unread
        ? Color.lerp(
            AppColors.paperAlt,
            accent,
            AppColors.isLight ? 0.08 : 0.14,
          )!
        : AppColors.paperAlt;

    return Semantics(
      button: true,
      label: '${unread ? 'Unread. ' : ''}${n.text}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(
              color: unread ? AppColors.line : AppColors.lineSoft,
              width: unread ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.line,
                offset: unread ? const Offset(3, 3) : const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  color: unread ? accent : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            TappableAvatar(
                              size: 42,
                              heroTag: 'notification:${n.id}',
                              name: n.actor.displayName,
                              image: avatarImage(n.actor.profilePic),
                            ),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.line,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  _icon,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: n.actor.displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    TextSpan(text: ' ${n.kind.action}'),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: unread
                                      ? AppColors.text
                                      : AppColors.text.withValues(alpha: 0.72),
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '@${n.actor.username} · '
                                '${formatChatListTime(context, n.createdAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.fieldLabel.copyWith(
                                  fontSize: 9,
                                  color: unread
                                      ? AppColors.primaryPale
                                      : AppColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                              border: Border.all(
                                color: AppColors.line,
                                width: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What shows behind a card while it is being swiped away.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.rust,
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            'REMOVE',
            style: AppTextStyles.fieldLabel.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 34, color: AppColors.textDim),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: AppTextStyles.body),
        if (actionLabel != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: onAction == null ? null : () => onAction!(),
            child: Text(actionLabel!, style: AppTextStyles.linkText),
          ),
        ],
      ],
    );
  }
}
