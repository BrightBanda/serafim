// lib/src/presentation/viewmodel/chat_view_model.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';

class ChatState {
  final bool isConnected;
  const ChatState({this.isConnected = false});

  ChatState copyWith({bool? isConnected}) {
    return ChatState(isConnected: isConnected ?? this.isConnected);
  }
}

Future<void> _eventQueue = Future.value();

class ChatViewModel extends Notifier<ChatState> {
  @override
  ChatState build() {
    ref.listen<AsyncValue<Map<String, dynamic>>>(webSocketStreamProvider, (
      previous,
      next,
    ) {
      next.whenData((data) {
        _eventQueue = _eventQueue.then((_) => _persistIncoming(data));
      });
    });
    return const ChatState();
  }

  Future<void> _persistIncoming(Map<String, dynamic> data) async {
    final isar = ref.read(isarServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final type = data['type'];

    switch (type) {
      case 'message':
        // Verify the message is actually addressed to the current user.
        // The server should only send us messages where we are the recipient,
        // but we double-check here to prevent leaking messages from other
        // conversations (e.g. when roomId is used as a sender id).
        final recipientId = data['recipient_id']?.toString();
        if (currentUser == null || recipientId != currentUser.id) {
          return; // Not for us; ignore.
        }

        final senderId = data['sender_id'].toString();
        final roomId = buildRoomId(senderId, currentUser.id);

        final msg = LocalMessage()
          ..messageId = data['message_id'] as String
          ..roomId = roomId
          ..senderId = senderId
          ..recipientId =
              recipientId! // Safe: checked above (non-null guard)
          ..textContent = data['content'] as String?
          ..status = _statusFromString(data['status'] as String?)
          ..timestamp = _parseServerTimestamp(data['timestamp'] as String?);
        await isar.saveMessage(msg);
        break;

      case 'message_ack':
      case 'message_status':
        final tempId = data['temp_id'] as String?;
        final realId = data['message_id'] as String?;
        final status = _statusFromString(data['status'] as String?);
        final serverTimestamp = data['timestamp'] != null
            ? _parseServerTimestamp(data['timestamp'] as String?)
            : null;
        print(
          '[ack] type=$type tempId=$tempId realId=$realId ts=$serverTimestamp',
        );

        if (tempId != null) {
          await isar.updateMessageStatus(
            tempId,
            status,
            newMessageId: realId,
            newTimestamp: serverTimestamp,
          );
        } else if (realId != null) {
          await isar.updateMessageStatus(
            realId,
            status,
            newTimestamp: serverTimestamp,
          );
        }
        break;

      case 'status':
        final isConnectedNow = data['status'] == 'connected';
        state = state.copyWith(isConnected: isConnectedNow);

        // When connection is re-established, resend any queued/pending messages
        if (isConnectedNow) {
          await _resendPendingMessages();
        }
        break;
    }
  }

  /// Builds a deterministic, order-independent room id for a 1:1 conversation
  /// between [userA] and [userB] so both sides arrive at the same value.
  static String buildRoomId(String userA, String userB) {
    return userA.compareTo(userB) < 0 ? '${userA}_$userB' : '${userB}_$userA';
  }

  /// Queries Isar for messages with 'sending' status and pushes them down the socket
  Future<void> _resendPendingMessages() async {
    final isar = ref.read(isarServiceProvider);

    // Fetch pending messages saved in Isar
    final pendingMessages = await isar.getPendingMessages();

    for (final msg in pendingMessages) {
      ref.read(webSocketServiceProvider).sendMessage({
        "type": "message",
        "temp_id": msg.messageId, // temp_id is stored in messageId before ack
        "recipient_id": msg.recipientId,
        "content": msg.textContent,
        "timestamp": msg.timestamp.toIso8601String(),
      });
    }
  }

  MessageStatus _statusFromString(String? s) {
    switch (s) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.sending;
    }
  }

  /// Send a chat message: write it locally first (instant UI update via
  /// the Isar watch stream), then attempt to push it over the socket.
  Future<void> sendMessage({
    required String roomId,
    required String recipientId,
    required String content,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final tempId = DateTime.now().microsecondsSinceEpoch.toString();
    final timestamp = DateTime.now().toUtc();
    final isar = ref.read(isarServiceProvider);

    final localMsg = LocalMessage()
      ..messageId = tempId
      ..roomId = roomId
      ..senderId = user.id
      ..recipientId = recipientId
      ..textContent = content
      ..status = MessageStatus.sending
      ..timestamp = timestamp;

    await isar.saveMessage(localMsg);

    // Try sending over socket; if offline, it remains saved in Isar as 'sending'
    // and will automatically resend via _resendPendingMessages() on reconnect.
    ref.read(webSocketServiceProvider).sendMessage({
      "type": "message",
      "temp_id": tempId,
      "recipient_id": recipientId,
      "content": content,
      "timestamp": timestamp.toIso8601String(),
    });
  }
}

final chatViewModelProvider = NotifierProvider<ChatViewModel, ChatState>(
  ChatViewModel.new,
);

DateTime _parseServerTimestamp(String? raw) {
  if (raw == null || raw.isEmpty) return DateTime.now().toUtc();
  final hasOffset =
      raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
  final normalized = hasOffset ? raw : '${raw}Z';
  return DateTime.tryParse(normalized)?.toUtc() ?? DateTime.now().toUtc();
}
