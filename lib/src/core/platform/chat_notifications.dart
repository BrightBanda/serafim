import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Color, DartPluginRegistrant;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart' show RemoteMessage;
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:serafim/src/core/config/app_config.dart';
import 'package:serafim/src/data/models/group.dart' show groupRoomId;
import 'package:shared_preferences/shared_preferences.dart';

/// A chat push that the app draws itself. The server sends these as data only
/// to phones registered with `notification_style: app` (see
/// `PushService.registerDevice`), so nothing replaces anything: every message
/// is listed under the earlier ones of the same conversation.
class ChatPush {
  const ChatPush({
    required this.messageId,
    required this.recipientId,
    required this.fromId,
    required this.title,
    required this.senderName,
    required this.text,
    this.groupId,
    this.replyToken,
  });

  final String messageId;

  /// The signed-in person the push is for.
  final String recipientId;
  final String fromId;

  /// The person's name in a 1:1 chat; the group's name in a group.
  final String title;

  /// Empty when previews are off and the push is a group message.
  final String senderName;
  final String text;
  final String? groupId;

  /// The server's reply link: lets the notification answer without the app.
  /// Missing when the server has no signing key, and then there's no Reply.
  final String? replyToken;

  bool get isGroup => groupId != null;

  /// Who a reply goes to: the person, or the group.
  String get target => groupId ?? fromId;

  String get roomId =>
      isGroup ? groupRoomId(groupId!) : directRoomId(recipientId, fromId);

  /// Null for any push that is not a chat message drawn by the app.
  static ChatPush? fromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type != 'message' && type != 'group_message') return null;
    final messageId = data['message_id'] as String?;
    final recipientId = data['recipient_id'] as String?;
    final fromId = data['from_id'] as String?;
    // Only data-only pushes carry these; a system notification never gets here.
    if (messageId == null || recipientId == null || fromId == null) return null;
    final groupId = type == 'group_message'
        ? data['group_id'] as String?
        : null;
    if (type == 'group_message' && groupId == null) return null;
    return ChatPush(
      messageId: messageId,
      recipientId: recipientId,
      fromId: fromId,
      groupId: groupId,
      title: (data['title'] as String?) ?? 'Serafim',
      senderName: (data['sender_name'] as String?) ?? '',
      text: (data['text'] as String?) ?? (data['body'] as String?) ?? '',
      replyToken: data['reply'] as String?,
    );
  }
}

/// The room id of a 1:1 chat, as `ChatViewModel.buildRoomId` makes it.
String directRoomId(String a, String b) =>
    a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

/// One line of a conversation notification.
@visibleForTesting
class NotifiedLine {
  const NotifiedLine({
    required this.id,
    required this.fromId,
    required this.name,
    required this.text,
    required this.at,
    this.mine = false,
  });

  final String id;
  final String fromId;
  final String name;
  final String text;
  final DateTime at;

  /// A reply typed into the notification.
  final bool mine;

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': fromId,
    'name': name,
    'text': text,
    'at': at.millisecondsSinceEpoch,
    if (mine) 'mine': true,
  };

  static NotifiedLine? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    return NotifiedLine(
      id: '${json['id']}',
      fromId: '${json['from']}',
      name: '${json['name']}',
      text: '${json['text']}',
      at: DateTime.fromMillisecondsSinceEpoch(at is int ? at : 0),
      mine: json['mine'] == true,
    );
  }
}

/// A reply typed into a notification, waiting for the app to put it in the
/// chat's history. The server usually has it already (sent straight from the
/// notification); the app then sends it once more with the same [clientId],
/// which the server only confirms. If the notification could not send it,
/// that send is the real one.
class QueuedReply {
  const QueuedReply({
    required this.clientId,
    required this.userId,
    required this.target,
    required this.text,
    required this.at,
    this.isGroup = false,
  });

  final String clientId;

  /// Who was signed in when it was typed.
  final String userId;

  /// The person replied to, or the group.
  final String target;
  final bool isGroup;
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'user': userId,
    'target': target,
    if (isGroup) 'group': true,
    'text': text,
    'at': at.toUtc().toIso8601String(),
  };

  static QueuedReply? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (json['client_id'] is! String || json['user'] is! String) return null;
    if (json['target'] is! String || json['text'] is! String || at == null) {
      return null;
    }
    return QueuedReply(
      clientId: json['client_id'] as String,
      userId: json['user'] as String,
      target: json['target'] as String,
      isGroup: json['group'] == true,
      text: json['text'] as String,
      at: at.toUtc(),
    );
  }
}

/// Where replies typed into notifications wait for the app (so tests can
/// stand in for the device's notifications).
abstract interface class NotificationReplyQueue {
  /// Replies the app has not recorded yet, oldest first.
  Future<List<QueuedReply>> queuedReplies();

  /// The app has recorded the reply [clientId].
  Future<void> forgetReply(String clientId);
}

/// What a tapped notification points at, for opening the chat.
class NotificationTarget {
  const NotificationTarget({required this.target, required this.isGroup});

  final String target;
  final bool isGroup;
}

/// Called by the plugin for a Reply typed into a notification. Always runs in
/// a background isolate (also while the app is open), so it only uses what
/// works there: preferences, plain HTTP and the notification plugin.
@pragma('vm:entry-point')
Future<void> onChatNotificationAction(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await ChatNotifications.instance.handleAction(response);
}

/// Chat notifications on Android: one per conversation, listing the latest
/// messages (Android's messaging style), with a Reply field. Used from the
/// app and from the background isolates that FCM and the notification plugin
/// start, so its state lives in preferences, not in memory.
class ChatNotifications implements NotificationReplyQueue {
  ChatNotifications._();

  static final instance = ChatNotifications._();

  static const _channelId = 'messages'; // made by MainActivity, as before
  static const _replyAction = 'reply';
  static const _historyPrefix = 'chatNotif.history.';
  static const _replyPrefix = 'chatNotif.reply.';

  /// Lines kept per conversation: what fits in an expanded notification.
  static const maxLines = 8;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  late final _plugin = FlutterLocalNotificationsPlugin();
  late final _prefs = SharedPreferencesAsync();
  Future<void>? _ready;

  void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[chat-notifications] $message');
    }
  }

  /// Sets up the plugin. [onTap] runs (in the app) when a notification is
  /// tapped; the background isolates pass nothing.
  Future<void> init({void Function(NotificationTarget target)? onTap}) {
    if (!supported) return Future.value();
    return _ready ??= _plugin
        .initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_stat_serafim'),
          ),
          onDidReceiveNotificationResponse: (response) {
            final target = targetOf(response.payload);
            if (target != null && onTap != null) onTap(target);
          },
          // Every isolate registers the same handler, so none can unset it.
          onDidReceiveBackgroundNotificationResponse: onChatNotificationAction,
        )
        .then((_) {});
  }

  /// The chat a notification tap should open when the app was launched by
  /// one, or null.
  Future<NotificationTarget?> launchTarget() async {
    if (!supported) return null;
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return targetOf(details!.notificationResponse?.payload);
  }

  /// Adds [push] to its conversation's notification and shows it.
  Future<void> show(ChatPush push) async {
    if (!supported) return;
    await init();
    final lines = await _history(push.roomId);
    // The same message can come twice (the socket and a push); list it once.
    if (lines.any((l) => l.id == push.messageId)) return;
    lines.add(
      NotifiedLine(
        id: push.messageId,
        fromId: push.fromId,
        name: push.isGroup
            ? (push.senderName.isEmpty ? push.title : push.senderName)
            : push.title,
        text: push.text,
        at: DateTime.now(),
      ),
    );
    await _saveHistory(push.roomId, lines);
    await _render(
      roomId: push.roomId,
      title: push.title,
      isGroup: push.isGroup,
      target: push.target,
      userId: push.recipientId,
      replyToken: push.replyToken,
      lines: lines,
    );
  }

  /// The conversation was opened in the app: its notification goes.
  Future<void> clear(String roomId) async {
    if (!supported) return;
    try {
      await init();
      await _plugin.cancel(id: notificationIdFor(roomId));
      await _prefs.remove('$_historyPrefix$roomId');
    } catch (error) {
      _log('could not clear $roomId: $error');
    }
  }

  /// Signing out: no conversation stays on screen, and nothing waits to send.
  Future<void> clearAll() async {
    if (!supported) return;
    try {
      await init();
      await _plugin.cancelAll();
      final keys = await _prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_historyPrefix) || key.startsWith(_replyPrefix)) {
          await _prefs.remove(key);
        }
      }
    } catch (error) {
      _log('could not clear notifications: $error');
    }
  }

  @override
  Future<List<QueuedReply>> queuedReplies() async {
    if (!supported) return const [];
    final all = await _prefs.getAll();
    final replies = <QueuedReply>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_replyPrefix)) continue;
      final value = entry.value;
      final reply = value is String
          ? QueuedReply.fromJson(_decode(value))
          : null;
      if (reply != null) replies.add(reply);
    }
    replies.sort((a, b) => a.at.compareTo(b.at));
    return replies;
  }

  @override
  Future<void> forgetReply(String clientId) =>
      _prefs.remove('$_replyPrefix$clientId');

  /// A Reply typed into a notification (in a background isolate).
  Future<void> handleAction(NotificationResponse response) async {
    if (response.actionId != _replyAction) return;
    final payload = _decode(response.payload);
    if (payload is! Map) return;
    final roomId = payload['room'] as String?;
    final target = payload['target'] as String?;
    final userId = payload['user'] as String?;
    final title = payload['title'] as String? ?? 'Serafim';
    final isGroup = payload['group'] == true;
    final token = payload['reply'] as String?;
    if (roomId == null || target == null || userId == null) return;
    await init();

    final text = response.input?.trim() ?? '';
    final lines = await _history(roomId);
    if (text.isEmpty) {
      // Re-shown, or Android keeps a spinner on the notification.
      await _render(
        roomId: roomId,
        title: title,
        isGroup: isGroup,
        target: target,
        userId: userId,
        replyToken: token,
        lines: lines,
        quiet: true,
      );
      return;
    }

    final reply = QueuedReply(
      clientId: 'n${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      target: target,
      isGroup: isGroup,
      text: text,
      at: DateTime.now().toUtc(),
    );
    // Queued first: whatever happens next, the app sends it when it opens.
    await _prefs.setString(
      '$_replyPrefix${reply.clientId}',
      jsonEncode(reply.toJson()),
    );
    final sent = token != null && await _send(token, reply);

    lines.add(
      NotifiedLine(
        id: reply.clientId,
        fromId: userId,
        name: 'You',
        text: text,
        at: DateTime.now(),
        mine: true,
      ),
    );
    await _saveHistory(roomId, lines);
    await _render(
      roomId: roomId,
      title: title,
      isGroup: isGroup,
      target: target,
      userId: userId,
      replyToken: token,
      lines: lines,
      quiet: true,
      note: sent ? null : 'Not sent yet. It will send when you open Serafim.',
    );
  }

  Future<bool> _send(String token, QueuedReply reply) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.fromEnvironment().apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        contentType: Headers.jsonContentType,
      ),
    );
    try {
      await dio.post<dynamic>(
        '/messages/reply',
        data: {
          'token': token,
          'content': reply.text,
          'client_id': reply.clientId,
        },
      );
      return true;
    } catch (error) {
      _log('reply not sent from the notification: $error');
      return false;
    } finally {
      dio.close();
    }
  }

  Future<void> _render({
    required String roomId,
    required String title,
    required bool isGroup,
    required String target,
    required String userId,
    required String? replyToken,
    required List<NotifiedLine> lines,
    bool quiet = false,
    String? note,
  }) async {
    if (lines.isEmpty) return;
    final me = const Person(name: 'You', key: 'me');
    final style = MessagingStyleInformation(
      me,
      conversationTitle: isGroup ? title : null,
      groupConversation: isGroup,
      messages: [
        for (final line in lines)
          Message(
            line.text,
            line.at,
            line.mine ? null : Person(name: line.name, key: line.fromId),
          ),
      ],
    );
    final payload = jsonEncode({
      'room': roomId,
      'target': target,
      'user': userId,
      'title': title,
      if (isGroup) 'group': true,
      'reply': ?replyToken,
    });
    await _plugin.show(
      id: notificationIdFor(roomId),
      title: title,
      body: lines.last.text,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Messages',
          channelDescription: 'New messages from your conversations',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          icon: 'ic_stat_serafim',
          color: const Color(0xFF5B7FD6),
          styleInformation: style,
          subText: note,
          // A reply re-shows the notification; that must not buzz again.
          onlyAlertOnce: quiet,
          silent: quiet,
          when: lines.last.at.millisecondsSinceEpoch,
          actions: [
            if (replyToken != null)
              const AndroidNotificationAction(
                _replyAction,
                'Reply',
                inputs: [AndroidNotificationActionInput(label: 'Message')],
                // Kept open: it is re-shown with the reply in it.
                cancelNotification: false,
                semanticAction: SemanticAction.reply,
              ),
          ],
        ),
      ),
    );
  }

  Future<List<NotifiedLine>> _history(String roomId) async {
    final raw = await _prefs.getString('$_historyPrefix$roomId');
    final decoded = _decode(raw);
    if (decoded is! List) return [];
    return [
      for (final item in decoded)
        if (NotifiedLine.fromJson(item) case final line?) line,
    ];
  }

  Future<void> _saveHistory(String roomId, List<NotifiedLine> lines) {
    final kept = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;
    return _prefs.setString(
      '$_historyPrefix$roomId',
      jsonEncode([for (final line in kept) line.toJson()]),
    );
  }

  static Object? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// The chat a notification's payload points at.
  static NotificationTarget? targetOf(String? payload) {
    final data = _decode(payload);
    if (data is! Map || data['target'] is! String) return null;
    return NotificationTarget(
      target: data['target'] as String,
      isGroup: data['group'] == true,
    );
  }
}

/// A stable notification id for a conversation (FNV-1a, 31 bits), the same
/// in every isolate and every run.
@visibleForTesting
int notificationIdFor(String roomId) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(roomId)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// FCM's handler for pushes that arrive while the app is not on screen (a
/// background isolate; see `FirebaseMessaging.onBackgroundMessage`). Chat
/// pushes are drawn here; anything else was already shown by the system.
@pragma('vm:entry-point')
Future<void> onBackgroundPush(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  final push = ChatPush.fromData(message.data);
  if (push != null) await ChatNotifications.instance.show(push);
}
