import 'package:cached_network_image/cached_network_image.dart';
// lib/src/presentation/viewmodel/chat_viewmodel.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart' show Icon, Icons;
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/presentation/view/notifications_page.dart';
import 'package:serafim/src/presentation/view/official_chat_page.dart';
import 'package:serafim/src/providers/notification_providers.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/local/isar_service.dart' show previewTextOf;
import 'package:serafim/src/utils/group_nav.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/typing_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
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
        // "Typing…" is live-only: straight to its own small tracker, ahead of
        // the persistence queue, so it is never delayed behind database writes.
        final kind = data['type'];
        if (kind == 'typing') {
          ref.read(typingProvider.notifier).heard(data);
          return;
        }
        if (kind == 'message') {
          // Their message arrived, so they are not "typing" it any more.
          final sender = data['sender_id'] as String?;
          final me = ref.read(currentAccountIdProvider);
          if (sender != null && me != null) {
            final gid = data['group_id'] as String?;
            ref
                .read(typingProvider.notifier)
                .stopped(
                  gid != null ? groupRoomId(gid) : buildRoomId(me, sender),
                  sender,
                );
          }
        }
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

  /// Tells the other side you started or stopped typing. Live only: if the
  /// socket is down it is simply dropped (nobody wants a late "typing…").
  void sendTyping({
    required String recipientId,
    String? groupId,
    required bool typing,
  }) {
    ref.read(webSocketServiceProvider).sendMessage({
      'type': 'typing',
      if (groupId != null) 'group_id': groupId else 'recipient_id': recipientId,
      'state': typing,
    });
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
          avatar: pic != null && pic.isNotEmpty
              ? CachedNetworkImageProvider(pic)
              : null,
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

  /// Banner for a friend request, accepted request or new follower.
  void _alertNotification(Map<String, dynamic> data) {
    final settings = ref.read(settingsProvider);
    if (!settings.inAppAlerts) return;
    final id = data['id'] as String?;
    final shown = ref.read(shownAlertIdsProvider);
    if (id != null && !shown.add('notification:$id:${data['kind']}')) return;
    if (shown.length > 100) shown.remove(shown.first);

    final kind = NotificationKind.parse(data['kind'] as String?);
    final name = (data['actor_name'] as String?) ?? 'Someone';
    final pic = data['actor_pic'] as String?;
    ref
        .read(inAppBannerProvider)
        .show(
          label: kind.bannerLabel,
          icon: switch (kind) {
            NotificationKind.friendRequest => Icons.person_add_alt_1_rounded,
            NotificationKind.friendAccepted => Icons.people_alt_rounded,
            NotificationKind.newFollower => Icons.favorite_rounded,
            NotificationKind.unknown => Icons.notifications_rounded,
            _ => Icons.groups_rounded,
          },
          accent: switch (kind) {
            NotificationKind.friendAccepted => AppColors.teal,
            NotificationKind.newFollower => AppColors.rust,
            _ when kind.isCircle => AppColors.teal,
            _ => AppColors.primary,
          },
          title: name,
          body: kind.action[0].toUpperCase() + kind.action.substring(1),
          avatar: pic != null && pic.isNotEmpty
              ? CachedNetworkImageProvider(pic)
              : null,
          onTap: () {
            final navigator = ref.read(navigatorKeyProvider).currentState;
            if (navigator != null) openNotificationsWithNavigator(navigator);
          },
        );
    if (settings.alertSound) SystemSound.play(SystemSoundType.alert);
  }

  /// Banner for a new official announcement, unless that chat is open.
  void _alertAnnouncement(Announcement announcement) {
    final settings = ref.read(settingsProvider);
    if (!settings.inAppAlerts) return;
    if (ref.read(activeRoomProvider) == officialRoomId) return;
    final shown = ref.read(shownAlertIdsProvider);
    if (!shown.add('announcement:${announcement.id}')) return;
    if (shown.length > 100) shown.remove(shown.first);

    ref
        .read(inAppBannerProvider)
        .show(
          label: 'OFFICIAL ANNOUNCEMENT',
          icon: Icons.campaign_rounded,
          title: 'SERAFIM',
          body: announcement.preview,
          leading: const SerafimMark(size: 42),
          onTap: () {
            final navigator = ref.read(navigatorKeyProvider).currentState;
            if (navigator != null) openOfficialChatWithNavigator(navigator);
          },
        );
    if (settings.alertSound) SystemSound.play(SystemSoundType.alert);
  }

  /// Who sent it: from the friends list if possible, otherwise looked up by id
  /// (briefly — an unreachable server must not delay the banner for long).
  Future<PublicUser?> _senderProfile(String senderId) async {
    final friends = ref.read(friendsViewProvider).friends;
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
        case 'message' when data['group_id'] != null:
          await _persistGroupMessage(data, live: true);
          break;

        case 'group_update':
          final gid = data['group_id'] as String?;
          if (gid != null) ref.invalidate(groupDetailProvider(gid));
          await ref.read(myGroupsProvider.notifier).reload();
          break;

        case 'group_removed':
          // Removed from a group: it, its messages and its media go from
          // this device too.
          final gid = data['group_id'] as String?;
          if (gid != null) await GroupActions.forget(ref, gid);
          break;

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

          final isSticker = data['kind'] == 'sticker';
          final isVoice = data['kind'] == 'voice';
          final msg = LocalMessage()
            ..messageId = messageId
            ..roomId = roomId
            ..senderId = senderId
            ..recipientId =
                recipientId! // Safe: checked above
            ..textContent = data['content'] as String?
            ..localMediaPath = mediaPath
            ..replyToId = data['reply_to'] as String?
            ..type = isSticker
                ? MessageType.sticker
                : isVoice
                ? MessageType.audio
                : mediaPath != null
                ? MessageType.image
                : MessageType.text
            ..mediaRemoteId = isVoice ? data['media_id'] as String? : null
            ..durationMs = isVoice ? data['duration_ms'] as int? : null
            ..waveform = isVoice
                ? [
                    for (final v in (data['waveform'] as List? ?? const []))
                      v as int,
                  ]
                : null
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
            text: isSticker
                ? '🙂 Sticker'
                : isVoice
                ? '🎤 Voice message'
                : msg.textContent,
            isImage: mediaPath != null,
          );
          // Fetch the audio now, so it plays instantly (and offline) later.
          if (isVoice && msg.mediaRemoteId != null) {
            unawaited(downloadVoice(messageId));
          }
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
          final notice = rejectionNotice(data);
          // Looked up before the status change so we know which chat it was.
          final roomId = notice != null && tempId != null
              ? (await isar.getMessageById(tempId))?.roomId
              : null;
          if (tempId != null) {
            await isar.updateMessageStatus(tempId, MessageStatus.failed);
          }
          _log('message rejected: ${data['reason']}');
          // Only while that chat is open: elsewhere the failed tick is enough.
          if (notice != null &&
              roomId != null &&
              ref.read(activeRoomProvider) == roomId) {
            ref
                .read(inAppBannerProvider)
                .show(
                  label: 'NOT SENT',
                  icon: Icons.error_outline_rounded,
                  accent: AppColors.rust,
                  leading: Icon(
                    Icons.person_off_rounded,
                    size: 32,
                    color: AppColors.rust,
                  ),
                  title: notice,
                  body: '',
                );
          }
          break;

        case 'action_rejected':
          _log('${data['action']} rejected: ${data['reason']}');
          break;

        case 'friend_update':
          SocialActions.refreshAll(ref);
          // An undone follow or request also takes its notification away.
          ref.invalidate(notificationsProvider);
          break;

        case 'notification':
          ref.invalidate(notificationsProvider);
          _alertNotification(data);
          break;

        case 'announcement':
          final announcement = Announcement.fromJson(data);
          ref.read(officialChatProvider.notifier).receive(announcement);
          _alertAnnouncement(announcement);
          break;

        case 'announcement_deleted':
          final id = data['id'] as String?;
          if (id != null) {
            ref.read(officialChatProvider.notifier).removeLocal(id);
          }
          break;

        case 'status':
          final isConnectedNow = data['status'] == 'connected';
          state = state.copyWith(isConnected: isConnectedNow);

          if (isConnectedNow) {
            await _resendPendingMessages();
            // Anything that happened while we were offline.
            await _flushReadAcks();
            await _syncMessageStates();
            // Group messages are not queued per person: catch up from history.
            unawaited(_syncGroups());
          }
          break;
      }
    } catch (error, stackTrace) {
      _log(
        'Error persisting incoming event payload $data: $error\n$stackTrace',
      );
    }
  }

  /// Stores one group message (live from the socket, or from history),
  /// applying edits/deletions to ones already here.
  Future<void> _persistGroupMessage(
    Map<String, dynamic> data, {
    required bool live,
  }) async {
    final me = ref.read(currentUserProvider)?.id;
    final gid = data['group_id']?.toString();
    final messageId = data['message_id']?.toString();
    if (me == null || gid == null || messageId == null) return;
    final isar = ref.read(isarServiceProvider);

    final existing = await isar.getMessageById(messageId);
    if (existing != null) {
      if (data['deleted'] == true) {
        await isar.applyDelete(messageId);
      } else if (data['edited_at'] != null && data['content'] is String) {
        await isar.applyEdit(
          messageId,
          data['content'] as String,
          _parseServerTimestamp(data['edited_at'] as String?),
        );
      }
      return;
    }

    final senderId = data['sender_id'].toString();
    final kind = data['kind'] as String? ?? 'text';
    final deleted = data['deleted'] == true;
    final msg = LocalMessage()
      ..messageId = messageId
      ..roomId = groupRoomId(gid)
      ..groupId = gid
      ..senderId = senderId
      ..recipientId = gid
      ..textContent = deleted ? null : data['content'] as String?
      ..replyToId = data['reply_to'] as String?
      ..type = switch (kind) {
        'sticker' when !deleted => MessageType.sticker,
        'voice' when !deleted => MessageType.audio,
        _ => MessageType.text,
      }
      ..mediaRemoteId = kind == 'voice' ? data['media_id'] as String? : null
      ..durationMs = data['duration_ms'] as int?
      ..waveform = [
        for (final v in (data['waveform'] as List? ?? const [])) v as int,
      ]
      ..isDeleted = deleted
      ..editedAt = data['edited_at'] != null
          ? _parseServerTimestamp(data['edited_at'] as String?)
          : null
      ..status = MessageStatus.sent
      ..timestamp = _parseServerTimestamp(data['timestamp'] as String?);
    await isar.saveMessage(msg);

    if (msg.type == MessageType.audio && msg.mediaRemoteId != null) {
      unawaited(downloadVoice(messageId));
    }
    if (live && senderId != me) {
      _alertGroupMessage(
        messageId: messageId,
        groupId: gid,
        senderId: senderId,
        text: previewTextOf(msg),
      );
    }
  }

  bool _syncingGroups = false;

  /// After (re)connecting: refreshes the group list, forgets groups we were
  /// removed from while away, and fetches messages we missed in the rest.
  Future<void> _syncGroups() async {
    if (_syncingGroups) return;
    _syncingGroups = true;
    try {
      final service = ref.read(groupServiceProvider);
      final isar = ref.read(isarServiceProvider);
      final groups = await service.mine();
      final ids = {for (final g in groups) g.id};
      await ref.read(myGroupsProvider.notifier).reload();

      final rooms = ref.read(chatRoomsProvider);
      for (final room in rooms) {
        if (!isGroupRoom(room.roomId)) continue;
        final gid = room.roomId.substring('group_'.length);
        if (!ids.contains(gid)) await GroupActions.forget(ref, gid);
      }

      for (final g in groups) {
        final after = await isar.latestTimestamp(g.roomId);
        final missed = await service.messagesSince(g.id, after: after);
        for (final m in missed) {
          await _persistGroupMessage(m, live: false);
        }
      }
    } catch (error) {
      _log('group sync failed: $error');
    } finally {
      _syncingGroups = false;
    }
  }

  void _alertGroupMessage({
    required String messageId,
    required String groupId,
    required String senderId,
    required String? text,
  }) {
    final settings = ref.read(settingsProvider);
    if (!settings.inAppAlerts) return;
    if (ref.read(activeRoomProvider) == groupRoomId(groupId)) return;
    final shown = ref.read(shownAlertIdsProvider);
    if (!shown.add(messageId)) return;
    if (shown.length > 100) shown.remove(shown.first);

    final group = ref.read(myGroupProvider(groupId));
    final sender =
        ref.read(knownPersonProvider(senderId))?.displayName ?? 'Someone';
    ref
        .read(inAppBannerProvider)
        .show(
          label: 'GROUP MESSAGE',
          icon: Icons.groups_rounded,
          accent: AppColors.teal,
          title: group?.name ?? 'Group',
          body: '$sender: ${text ?? ''}',
          avatar: group?.photoUrl != null && group!.photoUrl!.isNotEmpty
              ? CachedNetworkImageProvider(group.photoUrl!)
              : null,
          onTap: () {
            final navigator = ref.read(navigatorKeyProvider).currentState;
            if (navigator != null && group != null) {
              openGroupChatWithNavigator(navigator, group);
            }
          },
        );
    if (settings.alertSound) SystemSound.play(SystemSoundType.alert);
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
      if (msg.type == MessageType.audio) {
        // A voice note may still need its upload (which is safe to repeat).
        unawaited(_deliverVoice(msg.messageId));
        continue;
      }
      ref
          .read(webSocketServiceProvider)
          .sendMessage(await _outgoingPayload(msg));
    }
  }

  Future<Map<String, dynamic>> _outgoingPayload(LocalMessage msg) async {
    final target = msg.groupId != null
        ? {"group_id": msg.groupId}
        : {"recipient_id": msg.recipientId};
    if (msg.type == MessageType.audio) {
      return {
        "type": "message",
        "temp_id": msg.messageId,
        ...target,
        "kind": "voice",
        "media_id": msg.mediaRemoteId,
        "content": "",
        if (msg.replyToId != null) "reply_to": msg.replyToId,
      };
    }
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
      ...target,
      "content": msg.textContent ?? '',
      if (msg.type == MessageType.sticker) "kind": "sticker",
      if (attachment != null) "attachment": attachment,
      if (attachment != null)
        "attachment_type": path!.endsWith('.gif') ? 'gif' : 'image',
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

  // ---- voice notes ----

  /// Voice notes being uploaded right now, so a retry or reconnect can never
  /// start a second upload of the same one.
  final Set<String> _voiceInFlight = {};

  /// Sends a recording: saved locally first (so it shows at once, with upload
  /// progress), uploaded, then announced over the socket.
  Future<void> sendVoice({
    required String roomId,
    required String recipientId,
    required String path,
    required int durationMs,
    required List<int> waveform,
    String? replyToId,
    String? groupId,
    // Set when forwarding: the audio is already on the server, so it is
    // sent as it is instead of being uploaded again.
    String? mediaRemoteId,
    bool forwarded = false,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final tempId = DateTime.now().microsecondsSinceEpoch.toString();
    final stored = mediaRemoteId == null
        ? await ref.read(chatMediaStoreProvider).adoptRecording(tempId, path)
        : path;

    final msg = LocalMessage()
      ..messageId = tempId
      ..roomId = roomId
      ..senderId = user.id
      ..recipientId = recipientId
      ..groupId = groupId
      ..textContent = ''
      ..localMediaPath = stored
      ..mediaRemoteId = mediaRemoteId
      ..durationMs = durationMs
      ..waveform = waveform
      ..replyToId = replyToId
      ..forwarded = forwarded
      ..type = MessageType.audio
      ..status = MessageStatus.sending
      ..timestamp = DateTime.now().toUtc();
    await ref.read(isarServiceProvider).saveMessage(msg);
    if (mediaRemoteId == null) {
      await _deliverVoice(tempId);
    } else {
      // Already uploaded: just tell the server about it.
      ref
          .read(webSocketServiceProvider)
          .sendMessage(await _outgoingPayload(msg));
    }
  }

  /// Tap-to-retry on a voice note that failed to send.
  Future<void> retryVoice(String messageId) async {
    await ref
        .read(isarServiceProvider)
        .updateMessageStatus(messageId, MessageStatus.sending);
    await _deliverVoice(messageId);
  }

  Future<void> _deliverVoice(String messageId) async {
    if (!_voiceInFlight.add(messageId)) return;
    final isar = ref.read(isarServiceProvider);
    final progress = ref.read(voiceUploadProgressProvider.notifier);
    try {
      var msg = await isar.getMessageById(messageId);
      if (msg == null || msg.type != MessageType.audio) return;
      if (msg.status != MessageStatus.sending) return; // Already through.

      if (msg.mediaRemoteId == null) {
        final path = msg.localMediaPath;
        if (path == null || !await File(path).exists()) {
          await isar.updateMessageStatus(messageId, MessageStatus.failed);
          return;
        }
        progress.set(messageId, 0);
        final uploaded = await ref
            .read(mediaServiceProvider)
            .uploadVoice(
              bytes: await File(path).readAsBytes(),
              // The temp id: uploading again after a failure returns the
              // first upload instead of a duplicate.
              clientId: messageId,
              durationMs: msg.durationMs ?? 0,
              waveform: msg.waveform ?? const [],
              recipientId: msg.groupId == null ? msg.recipientId : null,
              groupId: msg.groupId,
              onProgress: (p) => progress.set(messageId, p),
            );
        await isar.updateMedia(messageId, mediaRemoteId: uploaded.id);
        msg = await isar.getMessageById(messageId);
        if (msg == null) return;
      }
      // Offline: it stays "sending" and goes out on reconnect. The server
      // ignores a repeat of the same temp id.
      ref
          .read(webSocketServiceProvider)
          .sendMessage(await _outgoingPayload(msg));
    } catch (error) {
      _log('voice upload failed: $error');
      await isar.updateMessageStatus(messageId, MessageStatus.failed);
    } finally {
      progress.clear(messageId);
      _voiceInFlight.remove(messageId);
    }
  }

  /// Forwards a message to another chat.
  ///
  /// The people it goes to see an ordinary message; only the copy on this
  /// phone is labelled "Forwarded". There is no server change: a forward is
  /// just a new message with the same content.
  ///
  /// For a group, [recipientId] is the group's id and [groupId] is set.
  /// Returns false when the message cannot be forwarded at all.
  Future<bool> forwardMessage({
    required LocalMessage source,
    required String recipientId,
    String? groupId,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    if (source.isDeleted) return false;
    if (source.status == MessageStatus.sending ||
        source.status == MessageStatus.failed) {
      return false;
    }

    final roomId = groupId != null
        ? groupRoomId(groupId)
        : buildRoomId(user.id, recipientId);

    switch (source.type) {
      case MessageType.text:
        final text = source.textContent;
        if (text == null || text.isEmpty) return false;
        await sendMessage(
          roomId: roomId,
          recipientId: recipientId,
          content: text,
          groupId: groupId,
          forwarded: true,
        );
        return true;

      case MessageType.sticker:
        final stickerId = source.textContent;
        if (stickerId == null || stickerId.isEmpty) return false;
        await sendSticker(
          roomId: roomId,
          recipientId: recipientId,
          stickerId: stickerId,
          groupId: groupId,
          forwarded: true,
        );
        return true;

      case MessageType.audio:
        // The audio is already on the server, so it is sent as it is
        // rather than uploaded again.
        final mediaId = source.mediaRemoteId;
        final path = source.localMediaPath;
        if (mediaId == null || path == null) return false;
        await sendVoice(
          roomId: roomId,
          recipientId: recipientId,
          path: path,
          durationMs: source.durationMs ?? 0,
          waveform: source.waveform ?? const [],
          groupId: groupId,
          mediaRemoteId: mediaId,
          forwarded: true,
        );
        return true;

      case MessageType.image:
        // The server refuses attachments in groups, so the picker does not
        // offer them for a picture.
        if (groupId != null) return false;
        final path = source.localMediaPath;
        if (path == null) return false;
        final file = File(path);
        if (!await file.exists()) return false;
        await sendMessage(
          roomId: roomId,
          recipientId: recipientId,
          imageBytes: await file.readAsBytes(),
          groupId: null,
          forwarded: true,
        );
        return true;

      case MessageType.video:
        return false;
    }
  }

  final Set<String> _downloading = {};

  /// Fetches a received voice note's audio. Safe to call repeatedly; returns
  /// whether the audio is now on this device.
  Future<bool> downloadVoice(String messageId) async {
    final isar = ref.read(isarServiceProvider);
    final msg = await isar.getMessageById(messageId);
    if (msg == null || msg.mediaRemoteId == null) return false;
    final existing = msg.localMediaPath;
    if (existing != null && await File(existing).exists()) return true;
    if (!_downloading.add(messageId)) return false;
    try {
      final bytes = await ref
          .read(mediaServiceProvider)
          .download(msg.mediaRemoteId!);
      final path = await ref
          .read(chatMediaStoreProvider)
          .save(messageId, bytes, extension: 'm4a');
      await isar.updateMedia(messageId, localMediaPath: path);
      return true;
    } catch (error) {
      _log('voice download failed: $error');
      return false;
    } finally {
      _downloading.remove(messageId);
    }
  }

  /// Sends a sticker by its id (`pack/name`); the art ships with the app.
  Future<void> sendSticker({
    required String roomId,
    required String recipientId,
    required String stickerId,
    String? replyToId,
    String? groupId,
    bool forwarded = false,
  }) => sendMessage(
    roomId: roomId,
    recipientId: recipientId,
    content: stickerId,
    replyToId: replyToId,
    type: MessageType.sticker,
    groupId: groupId,
    forwarded: forwarded,
  );

  Future<void> sendMessage({
    required String roomId,
    required String recipientId,
    String content = '',
    Uint8List? imageBytes,
    String? replyToId,
    MessageType? type,
    String? groupId,
    bool forwarded = false,
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
      ..groupId = groupId
      ..textContent = content
      ..localMediaPath = mediaPath
      ..replyToId = replyToId
      ..forwarded = forwarded
      ..type =
          type ?? (mediaPath != null ? MessageType.image : MessageType.text)
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

/// What to tell the sender when the server refuses a message, or null when
/// the failed status says enough. Today only a suspended recipient
/// (`user_unavailable`) gets words; the server's own text wins when present.
@visibleForTesting
String? rejectionNotice(Map<String, dynamic> data) {
  if (data['reason'] != 'user_unavailable') return null;
  final message = data['message'];
  return message is String && message.trim().isNotEmpty
      ? message.trim()
      : 'User not available';
}

@visibleForTesting
DateTime parseServerTimestamp(String? raw) {
  if (raw == null || raw.isEmpty) return DateTime.now().toUtc();
  final hasOffset =
      raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
  final normalized = hasOffset ? raw : '${raw}Z';
  return DateTime.tryParse(normalized)?.toUtc() ?? DateTime.now().toUtc();
}
