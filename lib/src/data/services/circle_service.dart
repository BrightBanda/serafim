import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/circle.dart';

/// Talks to the backend's `/circles` routes. Membership and permissions are
/// checked by the server on every call — the app only hides what the person
/// cannot do, it never decides it.
class CircleService {
  const CircleService(this._dio);

  final Dio _dio;

  /// The Circles the signed-in person has joined.
  Future<List<CircleSummary>> mine() async {
    final data = await _call(() => _dio.get<dynamic>('/circles'));
    if (data is! List) throw _unexpected;
    return [
      for (final c in data) CircleSummary.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// Circles to look at: `for_you` matches the person's interests,
  /// `popular` is ordered by member count.
  Future<List<CircleSummary>> discover({
    String section = 'for_you',
    String? category,
    String? query,
  }) async {
    final data = await _call(
      () => _dio.get<dynamic>(
        '/circles/discover',
        queryParameters: {
          'section': section,
          if (category != null) 'category': category,
          if (query != null && query.isNotEmpty) 'q': query,
        },
      ),
    );
    if (data is! List) throw _unexpected;
    return [
      for (final c in data) CircleSummary.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<CircleDetail> detail(String id) async => CircleDetail.fromJson(
    await _map(() => _dio.get<dynamic>('/circles/$id')),
  );

  Future<CircleDetail> create({
    required String name,
    String? description,
    String? category,
    CircleVisibility visibility = CircleVisibility.public,
    String? rules,
  }) async => CircleDetail.fromJson(
    await _map(
      () => _dio.post<dynamic>(
        '/circles',
        data: {
          'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (category != null && category.isNotEmpty) 'category': category,
          'visibility': visibility.wire,
          if (rules != null && rules.isNotEmpty) 'rules': rules,
        },
      ),
    ),
  );

  /// Owner only. An empty string clears a text field.
  Future<CircleDetail> update(
    String id, {
    String? name,
    String? description,
    String? category,
    CircleVisibility? visibility,
    String? rules,
    bool? postingEnabled,
  }) async => CircleDetail.fromJson(
    await _map(
      () => _dio.put<dynamic>(
        '/circles/$id',
        data: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (category != null) 'category': category,
          if (visibility != null) 'visibility': visibility.wire,
          if (rules != null) 'rules': rules,
          if (postingEnabled != null) 'posting_enabled': postingEnabled,
        },
      ),
    ),
  );

  Future<void> delete(String id, {required String confirmName}) => _call(
    () => _dio.delete<dynamic>(
      '/circles/$id',
      queryParameters: {'confirm': confirmName},
    ),
  );

  /// Joins a public Circle, or asks to join a private one.
  Future<CircleSummary> join(String id) async => CircleSummary.fromJson(
    await _map(() => _dio.post<dynamic>('/circles/$id/join')),
  );

  Future<CircleLeaveResult> leave(String id) async =>
      CircleLeaveResult.fromJson(
        await _map(() => _dio.post<dynamic>('/circles/$id/leave')),
      );

  Future<List<CircleJoinRequest>> requests(String id) async {
    final data = await _call(() => _dio.get<dynamic>('/circles/$id/requests'));
    if (data is! List) throw _unexpected;
    return [
      for (final r in data)
        CircleJoinRequest.fromJson(r as Map<String, dynamic>),
    ];
  }

  Future<void> approve(String id, String requestId) => _call(
    () => _dio.post<dynamic>('/circles/$id/requests/$requestId/approve'),
  );

  Future<void> reject(String id, String requestId) => _call(
    () => _dio.post<dynamic>('/circles/$id/requests/$requestId/reject'),
  );

  Future<List<CircleMemberInfo>> members(String id) async {
    final data = await _call(() => _dio.get<dynamic>('/circles/$id/members'));
    if (data is! List) throw _unexpected;
    return [
      for (final m in data)
        CircleMemberInfo.fromJson(m as Map<String, dynamic>),
    ];
  }

  /// Owner only. [role] is an Overseer or a Member.
  Future<CircleDetail> setRole(
    String id,
    String userId,
    CircleRole role,
  ) async => CircleDetail.fromJson(
    await _map(
      () => _dio.put<dynamic>(
        '/circles/$id/members/$userId/role',
        data: {'role': role.name},
      ),
    ),
  );

  Future<CircleDetail> removeMember(String id, String userId) async =>
      CircleDetail.fromJson(
        await _map(() => _dio.delete<dynamic>('/circles/$id/members/$userId')),
      );

  Future<CircleDetail> ban(String id, String userId, {String? reason}) async =>
      CircleDetail.fromJson(
        await _map(
          () => _dio.post<dynamic>(
            '/circles/$id/ban/$userId',
            data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
          ),
        ),
      );

  Future<CircleDetail> transfer(String id, String userId) async =>
      CircleDetail.fromJson(
        await _map(
          () => _dio.post<dynamic>(
            '/circles/$id/transfer',
            data: {'user_id': userId},
          ),
        ),
      );

  /// Mutes the Circle, or chooses which notifications it sends.
  Future<CircleSummary> notificationSettings(
    String id, {
    bool? muted,
    bool? notifyPosts,
    bool? notifyReplies,
    bool? notifyMentions,
  }) async => CircleSummary.fromJson(
    await _map(
      () => _dio.put<dynamic>(
        '/circles/$id/settings/notifications',
        data: {
          if (muted != null) 'muted': muted,
          if (notifyPosts != null) 'notify_posts': notifyPosts,
          if (notifyReplies != null) 'notify_replies': notifyReplies,
          if (notifyMentions != null) 'notify_mentions': notifyMentions,
        },
      ),
    ),
  );

  static const _unexpected = ApiException(
    'The server sent an unexpected response.',
  );

  Future<Map<String, dynamic>> _map(
    Future<Response<dynamic>> Function() request,
  ) async {
    final data = await _call(request);
    if (data is! Map<String, dynamic>) throw _unexpected;
    return data;
  }

  Future<Object?> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
