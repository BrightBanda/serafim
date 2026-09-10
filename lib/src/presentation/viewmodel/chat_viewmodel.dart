// lib/src/presentation/viewmodel/chat_viewmodel.dart

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
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

class ChatViewModel extends Notifier<ChatState> {
  /// Every incoming socket event is chained onto this future, so events are
  /// guaranteed to be fully persisted one at a time, in the order they
  /// arrived — never concurrently, never out of order. Without this, a
  /// receive and an ack landing close together could run as overlapping
  /// async Isar writes with no guaranteed ordering between them.
  Future<void> _eventQueue = Future.value();

  @override
  ChatState build() {
    ref.listen<AsyncValue<Map<String, dynamic>>>(webSocketStreamProvider, (
      previous,
      next,
    ) {
      next.whenData((data) {
        _eventQueue = _eventQueue
            .then((_) => _persistIncoming(data))
            .catchError((Object error, StackTrace stackTrace) {
              _log(
                'Unhandled error in socket event queue: $error\n$stackTrace',
              );
            });
      });
    });

    return const ChatState();
  }

  void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[chat] $message');
    }
  }

  Future<void> _persistIncoming(Map<String, dynamic> data) async {
    try {
      final isar = ref.read(isarServiceProvider);
      final currentUser = ref.read(currentUserProvider);
      final type = data['type'];

      switch (type) {
        case 'message':
          final recipientId = data['recipient_id']?.toString();
          if (currentUser == null || recipientId != currentUser.id) {
            return; // Not for us; ignore.
          }

          final senderId = data['sender_id'].toString();
          final roomId = buildRoomId(senderId, currentUser.id);
          final rawTimestamp = data['timestamp'] as String?;
          final parsedTimestamp = _parseServerTimestamp(rawTimestamp);
          final messageId = data['message_id'] as String;

          _log(
            'recv message_id=$messageId raw_ts=$rawTimestamp '
            'parsed_ts=$parsedTimestamp content=${data['content']}',
          );

          final msg = LocalMessage()
            ..messageId = messageId
            ..roomId = roomId
            ..senderId = senderId
            ..recipientId =
                recipientId! // Safe: checked above
            ..textContent = data['content'] as String?
            ..status = _statusFromString(data['status'] as String?)
            ..timestamp = parsedTimestamp;
          await isar.saveMessage(msg);

          // Confirm real, on-device receipt. This is the ONLY signal the
          // server trusts to ever mark a message "delivered" — a socket
          // write succeeding on the server's end does not prove the
          // recipient's app actually received and persisted it (the
          // "ghost socket" problem: a dead connection can look healthy
          // to the server until a write finally fails).
          ref.read(webSocketServiceProvider).sendMessage({
            "type": "delivery_ack",
            "message_id": messageId,
          });
          break;

        case 'message_ack':
        case 'message_status':
          final tempId = data['temp_id'] as String?;
          final realId = data['message_id'] as String?;
          final status = _statusFromString(data['status'] as String?);
          final rawTimestamp = data['timestamp'] as String?;
          final serverTimestamp = rawTimestamp != null
              ? _parseServerTimestamp(rawTimestamp)
              : null;

          _log(
            'ack type=$type tempId=$tempId realId=$realId '
            'raw_ts=$rawTimestamp parsed_ts=$serverTimestamp',
          );

          bool updated = false;
          if (tempId != null) {
            updated = await isar.updateMessageStatus(
              tempId,
              status,
              newMessageId: realId,
              newTimestamp: serverTimestamp,
            );
          } else if (realId != null) {
            updated = await isar.updateMessageStatus(
              realId,
              status,
              newTimestamp: serverTimestamp,
            );
          }

          if (!updated) {
            // The row this ack refers to wasn't found. This should never
            // happen (the optimistic write is awaited before the socket
            // send), but if it ever does, we want it loud instead of a
            // silently stale timestamp.
            _log(
              'WARNING: ack for tempId=$tempId realId=$realId matched no '
              'local row — timestamp/status correction was dropped.',
            );
          }
          break;

        case 'status':
          final isConnectedNow = data['status'] == 'connected';
          state = state.copyWith(isConnected: isConnectedNow);

          if (isConnectedNow) {
            await _resendPendingMessages();
          }
          break;
      }
    } catch (error, stackTrace) {
      _log(
        'Error persisting incoming event payload $data: $error\n$stackTrace',
      );
    }
  }

  /// Builds a deterministic, order-independent room id for a 1:1 conversation
  /// between [userA] and [userB] so both sides arrive at the same value.
  static String buildRoomId(String userA, String userB) {
    return userA.compareTo(userB) < 0 ? '${userA}_$userB' : '${userB}_$userA';
  }

  Future<void> _resendPendingMessages() async {
    final isar = ref.read(isarServiceProvider);
    final pendingMessages = await isar.getPendingMessages();

    for (final msg in pendingMessages) {
      ref.read(webSocketServiceProvider).sendMessage({
        "type": "message",
        "temp_id": msg.messageId,
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

    // Awaited: guarantees the local row exists before we send over the
    // socket, so a fast-returning ack can never race ahead of this write.
    await isar.saveMessage(localMsg);

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

DateTime _parseServerTimestamp(String? raw) => parseServerTimestamp(raw);

@visibleForTesting
DateTime parseServerTimestamp(String? raw) {
  if (raw == null || raw.isEmpty) return DateTime.now().toUtc();
  final hasOffset =
      raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
  final normalized = hasOffset ? raw : '${raw}Z';
  return DateTime.tryParse(normalized)?.toUtc() ?? DateTime.now().toUtc();
}
