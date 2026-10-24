import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/notifications_page.dart';
import 'package:serafim/src/providers/notification_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Bell in the top bar with the number of unread notifications. On every main
/// page, so new notifications are never more than a tap away.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    final label = unread > 99 ? '99+' : '$unread';

    return Semantics(
      button: true,
      label: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(
                    color: unread > 0 ? AppColors.primary : AppColors.lineSoft,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  unread > 0
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  size: 14,
                  color: unread > 0 ? AppColors.primaryPale : AppColors.textDim,
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.rust,
                      border: Border.all(color: AppColors.line, width: 1.5),
                    ),
                    child: Text(
                      label,
                      style: AppTextStyles.fieldLabel.copyWith(
                        fontSize: 8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
