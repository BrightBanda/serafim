import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/data/services/notification_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(apiDioProvider));
});

/// The signed-in user's notifications, newest first, with the commands the
/// notifications page needs. Changes are shown at once and undone if the
/// server refuses them, so nothing is silently lost.
class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  NotificationService get _service => ref.read(notificationServiceProvider);

  /// Swiped away but not yet confirmed by the server: kept out of any refresh
  /// that lands in the meantime, so they cannot pop back.
  final Set<String> _dismissing = {};

  @override
  Future<List<AppNotification>> build() async {
    if (ref.watch(currentAccountIdProvider) == null) return const [];
    final list = await _service.list();
    return [
      for (final n in list)
        if (!_dismissing.contains(n.id)) n,
    ];
  }

  /// Re-reads the list (pull to refresh, or the server said something new).
  Future<void> reload() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // The page shows the error.
    }
  }

  /// Removes one notification. It disappears straight away; if the server
  /// refuses, it is put back where it was and the reason is returned.
  Future<String?> dismiss(String id) async {
    final current = state.value;
    if (current == null) return null;
    final index = current.indexWhere((n) => n.id == id);
    if (index < 0) return null;
    final removed = current[index];

    _dismissing.add(id);
    state = AsyncData([...current]..removeAt(index));
    try {
      await _service.delete(id);
      return null;
    } catch (error) {
      // Already gone on the server: that is what the user wanted.
      if (error is ApiException && error.isNotFound) return null;
      final now = state.value ?? const <AppNotification>[];
      if (!now.any((n) => n.id == id)) {
        state = AsyncData(
          [...now]..insert(index.clamp(0, now.length), removed),
        );
      }
      return humanError(error, fallback: "Couldn't remove that notification.");
    } finally {
      _dismissing.remove(id);
    }
  }

  /// Marks one notification read (shown at once, undone on failure).
  Future<String?> markRead(String id) =>
      _markRead((n) => n.id == id, ids: [id]);

  Future<String?> markAllRead() => _markRead((_) => true);

  Future<String?> _markRead(
    bool Function(AppNotification) which, {
    List<String>? ids,
  }) async {
    final current = state.value;
    if (current == null) return null;
    final changed = {
      for (final n in current)
        if (!n.isRead && which(n)) n.id,
    };
    if (changed.isEmpty) return null;

    state = AsyncData([
      for (final n in current)
        changed.contains(n.id) ? n.copyWith(isRead: true) : n,
    ]);
    try {
      await _service.markRead(ids: ids);
      return null;
    } catch (error) {
      final now = state.value ?? const <AppNotification>[];
      state = AsyncData([
        for (final n in now)
          changed.contains(n.id) ? n.copyWith(isRead: false) : n,
      ]);
      return humanError(error, fallback: "Couldn't update your notifications.");
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
      NotificationsController.new,
    );

/// How many notifications are unread, for the bell badge.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value;
  if (list == null) return 0;
  return list.where((n) => !n.isRead).length;
});
