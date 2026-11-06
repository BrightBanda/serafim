import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/models/group.dart' show groupRoomId;
import 'package:serafim/src/data/services/scheduled_message_service.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final scheduledMessageServiceProvider = Provider<ScheduledMessageService>(
  (ref) => ScheduledMessageService(ref.watch(apiDioProvider)),
);

/// The local room a scheduled message belongs to, for [me].
String roomOfScheduled(String me, ScheduledMessage m) => m.groupId != null
    ? groupRoomId(m.groupId!)
    : ChatViewModel.buildRoomId(me, m.recipientId ?? '');

/// Your scheduled messages that still need you: those waiting, and those that
/// failed. One that has gone out becomes an ordinary message in the chat.
class ScheduledMessagesController extends Notifier<List<ScheduledMessage>> {
  @override
  List<ScheduledMessage> build() {
    if (ref.watch(currentAccountIdProvider) == null) return const [];
    Future.microtask(refresh);
    return const [];
  }

  ScheduledMessageService get _service =>
      ref.read(scheduledMessageServiceProvider);

  /// Asks the server (at start, and on reconnecting): some may have gone out
  /// while the app was closed.
  Future<void> refresh() async {
    try {
      final all = await _service.list();
      if (!ref.mounted) return;
      final sent = [
        for (final m in all)
          if (m.status == ScheduledStatus.sent) m,
      ];
      state = [
        for (final m in all)
          if (m.status != ScheduledStatus.sent) m,
      ];
      for (final m in sent) {
        await _collect(m);
      }
    } catch (_) {
      // Offline: what is known stays, and the next connect tries again.
    }
  }

  /// A `scheduled_update` frame: one went out, or could not.
  Future<void> heard(Map<String, dynamic> frame) async {
    final m = ScheduledMessage.fromJson(frame);
    if (m.status == ScheduledStatus.sent) {
      state = [
        for (final x in state)
          if (x.id != m.id) x,
      ];
      await _collect(m);
    } else {
      state = [
        for (final x in state)
          if (x.id != m.id) x,
        m,
      ];
    }
  }

  /// Puts one that went out into this phone's history, then tells the server
  /// it need not keep it. Safe to repeat.
  Future<void> _collect(ScheduledMessage m) async {
    final me = ref.read(currentAccountIdProvider);
    final id = m.messageId;
    if (me == null || id == null) return;
    final isar = ref.read(isarServiceProvider);
    if (await isar.getMessageById(id) == null) {
      await isar.saveMessage(
        LocalMessage()
          ..messageId = id
          ..roomId = roomOfScheduled(me, m)
          ..senderId = me
          ..recipientId = m.groupId ?? m.recipientId ?? ''
          ..groupId = m.groupId
          ..textContent = m.content
          ..type = MessageType.text
          ..status = MessageStatus.sent
          ..timestamp = m.sentAt ?? m.sendAt,
      );
    }
    try {
      await _service.remove(m.id);
    } catch (_) {
      // It is saved; the next refresh finds it and asks again.
    }
  }

  Future<void> schedule({
    String? recipientId,
    String? groupId,
    required String content,
    required DateTime sendAt,
  }) async {
    final created = await _service.create(
      recipientId: recipientId,
      groupId: groupId,
      content: content,
      sendAt: sendAt,
    );
    if (ref.mounted) state = [...state, created];
  }

  Future<void> change(
    String id, {
    required String content,
    required DateTime sendAt,
  }) async {
    final changed = await _service.update(id, content: content, sendAt: sendAt);
    if (ref.mounted) {
      state = [for (final x in state) x.id == id ? changed : x];
    }
  }

  /// Cancels one that is waiting, or dismisses one that failed.
  Future<void> remove(String id) async {
    await _service.remove(id);
    if (ref.mounted) {
      state = [
        for (final x in state)
          if (x.id != id) x,
      ];
    }
  }
}

final scheduledMessagesProvider =
    NotifierProvider<ScheduledMessagesController, List<ScheduledMessage>>(
      ScheduledMessagesController.new,
    );

/// One chat's scheduled messages, soonest first.
final scheduledInRoomProvider = Provider.family<List<ScheduledMessage>, String>(
  (ref, roomId) {
    final me = ref.watch(currentAccountIdProvider);
    if (me == null) return const [];
    return [
      for (final m in ref.watch(scheduledMessagesProvider))
        if (roomOfScheduled(me, m) == roomId) m,
    ]..sort((a, b) => a.sendAt.compareTo(b.sendAt));
  },
);
