// lib/src/presentation/viewmodel/chat_viewmodel.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart' show NetworkImage;
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/user_card.dart';

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

    // Retention: clear old local messages at startup and whenever the choice
    // changes.
    ref.listen<int>(
      settingsProvider.select((s) => s.retentionDays),
      (_, days) => _applyRetention(days),
      fireImmediately: true,
    );

    return const ChatState();
  }

  Future<void> _applyRetention(int days) async {
    if (days <= 0) return;
    try {
      final cutoff = DateTime.now().toUtc().subtract(Duration(days: days));
      final removed = await ref
          .read(isarServiceProvider)
          .purgeOlderThan(cutoff);
      if (removed > 0) _log('retention: removed $removed old messages');
    } catch (error) {
      _log('retention failed: $error');
    }
  }

  /// Banner (and optional sound) for a new message in a conversation that is
  /// not on screen. Respects the notification settings. Names who it is from.
  Future<void> _alertNewMessage({
    required String messageId,
    required String roomId,
    required String senderId,
    required String? text,
    required bool isImage,
  }) async {
    final settings = ref.read(settingsProvider);
    if (!settings.inAppAlerts) return;
    if (ref.read(activeRoomProvider) == roomId) return;

    // The same message can also arrive as a push; announce it once.
    final shown = ref.read(shownAlertIdsProvider);
    if (!shown.add(messageId)) return;
    if (shown.length > 100) shown.remove(shown.first);

    final sender = await _senderProfile(senderId);
    // The user may have opened that chat while we were looking them up.
    if (!ref.mounted || ref.read(activeRoomProvider) == roomId) return;

    final body = isImage
        ? ((text ?? '').isEmpty ? '📷 Photo' : '📷 $text')
        : (text ?? '');
    final pic = sender?.profilePic;

    ref
        .read(inAppBannerProvider)
        .show(
          title: sender?.displayName ?? 'Someone',
          body: body,
          avatar: pic != null && pic.isNotEmpty ? NetworkImage(pic) : null,
          onTap: () {
            final navigator = ref.read(navigatorKeyProvider).currentState;
            if (navigator == null) return;
            openChatWithNavigator(
              navigator,
              sender ??
                  PublicUser(
                    id: senderId,
                    username: '',
                    displayName: 'Unknown user',
                  ),
            );
          },
        );
    if (settings.alertSound) SystemSound.play(SystemSoundType.alert);
  }

  /// Who sent it: from the friends list if possible, otherwise looked up by id
  /// (briefly — an unreachable server must not delay the banner for long).
  Future<PublicUser?> _senderProfile(String senderId) async {
    final friends = ref.read(friendsProvider).value ?? const <PublicUser>[];
    for (final f in friends) {
      if (f.id == senderId) return f;
    }
    try {
      return await ref
          .read(socialServiceProvider)
          .user(senderId)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
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

          final attachment = data['attachment'] as String?;

          final existing = await isar.getMessageById(messageId);
          if (existing != null) {
            // Redelivery of something we already stored (our earlier ack was
            // lost). Never overwrite local state — a 'read' message must stay
            // read — just re-confirm to the server.
            _sendAck('delivery_ack', messageId);
            if (existing.status == MessageStatus.read) {
              await _flushReadAcks();
            }
            break;
          }

          String? mediaPath;
          if (attachment != null && attachment.isNotEmpty) {
            mediaPath = await ref
                .read(chatMediaStoreProvider)
                .save(messageId, base64Decode(attachment));
          }

          final msg = LocalMessage()
            ..messageId = messageId
            ..roomId = roomId
            ..senderId = senderId
            ..recipientId =
                recipientId! // Safe: checked above
            ..textContent = data['content'] as String?
            ..localMediaPath = mediaPath
            ..replyToId = data['reply_to'] as String?
            ..type = mediaPath != null ? MessageType.image : MessageType.text
            ..editedAt = data['edited_at'] != null
                ? _parseServerTimestamp(data['edited_at'] as String?)
                : null
            ..status = _statusFromString(data['status'] as String?)
            ..timestamp = parsedTimestamp;
          await isar.saveMessage(msg);

          // Confirm real, on-device receipt. This is the ONLY signal the
          // server trusts to ever mark a message "delivered" — a socket
          // write succeeding on the server's end does not prove the
          // recipient's app actually received and persisted it (the
          // "ghost socket" problem: a dead connection can look healthy
          // to the server until a write finally fails).
          _sendAck('delivery_ack', messageId);

          _alertNewMessage(
            messageId: messageId,
            roomId: roomId,
            senderId: senderId,
            text: msg.textContent,
            isImage: mediaPath != null,
          );
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

          // Reconnect sync can also carry edits and deletions we missed.
          final syncedId = realId ?? tempId;
          if (syncedId != null) {
            if (data['deleted'] == true) {
              await isar.applyDelete(syncedId);
            } else if (data['content'] is String && data['edited_at'] != null) {
              await isar.applyEdit(
                syncedId,
                data['content'] as String,
                _parseServerTimestamp(data['edited_at'] as String?),
              );
            }
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

        case 'message_edited':
          final id = data['message_id'] as String?;
          final content = data['content'] as String?;
          if (id != null && content != null) {
            await isar.applyEdit(
              id,
              content,
              _parseServerTimestamp(data['edited_at'] as String?),
            );
          }
          break;

        case 'message_deleted':
          final id = data['message_id'] as String?;
          if (id != null) await isar.applyDelete(id);
          break;

        case 'message_rejected':
          // The server refused to accept this message (e.g. an attachment to
          // a non-friend). It was never stored, so it can only be failed.
          final tempId = data['temp_id'] as String?;
          if (tempId != null) {
            await isar.updateMessageStatus(tempId, MessageStatus.failed);
          }
          _log('message rejected: ${data['reason']}');
          break;

        case 'action_rejected':
          _log('${data['action']} rejected: ${data['reason']}');
          break;

        case 'friend_update':
          SocialActions.refreshAll(ref);
          break;

        case 'status':
          final isConnectedNow = data['status'] == 'connected';
          state = state.copyWith(isConnected: isConnectedNow);

          if (isConnectedNow) {
            await _resendPendingMessages();
            // Anything that happened while we were offline.
            await _flushReadAcks();
            await _syncMessageStates();
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

  void _sendAck(String type, String messageId) {
    ref.read(webSocketServiceProvider).sendMessage({
      "type": type,
      "message_id": messageId,
    });
  }

  Future<void> _resendPendingMessages() async {
    final isar = ref.read(isarServiceProvider);
    final pendingMessages = await isar.getPendingMessages();

    for (final msg in pendingMessages) {
      ref
          .read(webSocketServiceProvider)
          .sendMessage(await _outgoingPayload(msg));
    }
  }

  Future<Map<String, dynamic>> _outgoingPayload(LocalMessage msg) async {
    String? attachment;
    final path = msg.localMediaPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        attachment = base64Encode(await file.readAsBytes());
      }
    }
    return {
      "type": "message",
      "temp_id": msg.messageId,
      "recipient_id": msg.recipientId,
      "content": msg.textContent ?? '',
      if (attachment != null) "attachment": attachment,
      if (attachment != null) "attachment_type": "image",
      if (msg.replyToId != null) "reply_to": msg.replyToId,
      "timestamp": msg.timestamp.toIso8601String(),
    };
  }

  /// Tells the server about messages read while the socket was down.
  Future<void> _flushReadAcks() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final isar = ref.read(isarServiceProvider);

    final pending = await isar.getPendingReadAcks(user.id);
    final ids = pending
        .map((m) => m.messageId)
        .where(_looksLikeServerId)
        .toList();
    if (ids.isEmpty) return;

    final sent = ref.read(webSocketServiceProvider).sendMessage({
      "type": "read_ack",
      "message_ids": ids,
    });
    if (sent) await isar.clearReadAckPending(ids);
  }

  /// While we were offline the server's pushes for our messages (delivered,
  /// read, edited, deleted) were dropped. Send the ids of recent messages in
  /// both directions so the server can report their current state.
  Future<void> _syncMessageStates() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final ids = (await ref.read(isarServiceProvider).getRecentSyncIds(user.id))
        .where(_looksLikeServerId)
        .toList();
    if (ids.isEmpty) return;

    ref.read(webSocketServiceProvider).sendMessage({
      "type": "sync_status",
      "message_ids": ids,
    });
  }

  // Server ids are UUIDs; client temp ids are numeric and unknown to the server.
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static bool _looksLikeServerId(String id) => _uuid.hasMatch(id);

  /// Called while a conversation is on screen: marks everything incoming as
  /// read locally and tells the server (or queues that until reconnect).
  Future<void> markRoomRead(String roomId) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final isar = ref.read(isarServiceProvider);

    final ids = await isar.markRoomRead(roomId, user.id);

    if (!ref.read(settingsProvider).sendReadReceipts) {
      // Read locally (clears the unread badge) but tell no one.
      await isar.clearReadAckPending(ids);
      return;
    }
    if (state.isConnected) await _flushReadAcks();
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

  /// Edits the text of one of our own, already-sent messages. Returns null on
  /// success or a message to show. The change is applied locally when the
  /// server echoes `message_edited`, so every device agrees.
  Future<String?> editMessage(String messageId, String newText) async {
    final text = newText.trim();
    if (text.isEmpty) return 'A message cannot be empty.';
    if (!_looksLikeServerId(messageId)) {
      return 'Wait until the message has been sent.';
    }
    if (!state.isConnected) return 'You are offline. Try again when connected.';

    final sent = ref.read(webSocketServiceProvider).sendMessage({
      "type": "edit_message",
      "message_id": messageId,
      "content": text,
    });
    return sent ? null : 'Could not reach the server.';
  }

  /// "Delete for me": removes the message (and image file) from this device
  /// only. Works for any message, ours or theirs.
  Future<void> deleteForMe(String messageId) {
    return ref.read(isarServiceProvider).hideMessageForMe(messageId);
  }

  /// Deletes one of our own messages for everyone.
  Future<String?> deleteMessage(String messageId) async {
    if (!_looksLikeServerId(messageId)) {
      // Never reached the server (still sending, or failed): nobody else has
      // it, so removing it locally is the whole job.
      await ref.read(isarServiceProvider).deleteLocalMessage(messageId);
      return null;
    }
    if (!state.isConnected) return 'You are offline. Try again when connected.';

    final sent = ref.read(webSocketServiceProvider).sendMessage({
      "type": "delete_message",
      "message_id": messageId,
    });
    return sent ? null : 'Could not reach the server.';
  }

  Future<void> sendMessage({
    required String roomId,
    required String recipientId,
    String content = '',
    Uint8List? imageBytes,
    String? replyToId,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final tempId = DateTime.now().microsecondsSinceEpoch.toString();
    final timestamp = DateTime.now().toUtc();
    final isar = ref.read(isarServiceProvider);

    // Image stays on this device; only a relay copy goes over the socket.
    final mediaPath = imageBytes != null
        ? await ref.read(chatMediaStoreProvider).save(tempId, imageBytes)
        : null;

    final localMsg = LocalMessage()
      ..messageId = tempId
      ..roomId = roomId
      ..senderId = user.id
      ..recipientId = recipientId
      ..textContent = content
      ..localMediaPath = mediaPath
      ..replyToId = replyToId
      ..type = mediaPath != null ? MessageType.image : MessageType.text
      ..status = MessageStatus.sending
      ..timestamp = timestamp;

    // Awaited: guarantees the local row exists before we send over the
    // socket, so a fast-returning ack can never race ahead of this write.
    await isar.saveMessage(localMsg);

    ref
        .read(webSocketServiceProvider)
        .sendMessage(await _outgoingPayload(localMsg));
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
