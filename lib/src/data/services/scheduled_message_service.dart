import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

enum ScheduledStatus {
  pending,
  sent,
  failed;

  static ScheduledStatus parse(Object? raw) => ScheduledStatus.values
      .firstWhere((s) => s.name == raw, orElse: () => ScheduledStatus.pending);
}

/// A text waiting on the server for the time its sender chose.
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.content,
    required this.sendAt,
    this.recipientId,
    this.groupId,
    this.status = ScheduledStatus.pending,
    this.reason,
    this.messageId,
    this.sentAt,
  });

  final String id;
  final String? recipientId;
  final String? groupId;
  final String content;
  final DateTime sendAt;
  final ScheduledStatus status;

  /// Why it couldn't go ([ScheduledStatus.failed]).
  final String? reason;

  /// The message it became ([ScheduledStatus.sent]).
  final String? messageId;
  final DateTime? sentAt;

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) =>
      ScheduledMessage(
        id: json['id'].toString(),
        recipientId: json['recipient_id'] as String?,
        groupId: json['group_id'] as String?,
        content: json['content'] as String? ?? '',
        sendAt:
            DateTime.tryParse(json['send_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
        status: ScheduledStatus.parse(json['status']),
        reason: json['reason'] as String?,
        messageId: json['message_id'] as String?,
        sentAt: DateTime.tryParse(json['sent_at'] as String? ?? ''),
      );

  /// In words, for a message that couldn't go.
  String get failureText => switch (reason) {
    'not_a_member' => "You're no longer in this group.",
    'user_unavailable' => 'This person is not available.',
    _ => "This message couldn't be sent.",
  };
}

/// Talks to the backend's `/messages/scheduled` routes.
class ScheduledMessageService {
  const ScheduledMessageService(this._dio);

  final Dio _dio;

  /// Everything of yours: waiting, and gone out or failed since you last asked.
  Future<List<ScheduledMessage>> list() async {
    try {
      final data = (await _dio.get<dynamic>('/messages/scheduled')).data;
      if (data is! List) return const [];
      return [
        for (final e in data)
          if (e is Map<String, dynamic>) ScheduledMessage.fromJson(e),
      ];
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ScheduledMessage> create({
    String? recipientId,
    String? groupId,
    required String content,
    required DateTime sendAt,
  }) => _one(
    () => _dio.post<dynamic>(
      '/messages/scheduled',
      data: {
        'recipient_id': groupId == null ? recipientId : null,
        'group_id': groupId,
        'content': content,
        'send_at': sendAt.toUtc().toIso8601String(),
      },
    ),
  );

  Future<ScheduledMessage> update(
    String id, {
    required String content,
    required DateTime sendAt,
  }) => _one(
    () => _dio.put<dynamic>(
      '/messages/scheduled/$id',
      data: {'content': content, 'send_at': sendAt.toUtc().toIso8601String()},
    ),
  );

  /// Cancels one that is waiting, dismisses one that failed, or says one that
  /// went out is now in this phone's history.
  Future<void> remove(String id) async {
    try {
      await _dio.delete<dynamic>('/messages/scheduled/$id');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ScheduledMessage> _one(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final data = (await request()).data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Something went wrong. Please try again.');
      }
      return ScheduledMessage.fromJson(data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
