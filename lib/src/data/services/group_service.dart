import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/group.dart';

/// Talks to the backend's `/groups` routes. Membership and permissions are
/// checked by the server on every call.
class GroupService {
  const GroupService(this._dio);

  final Dio _dio;

  Future<({GroupDetail group, List<AddResult> results})> create({
    required String name,
    String? photoUrl,
    String? rules,
    List<String> memberIds = const [],
  }) async {
    final data = await _map(
      () => _dio.post<dynamic>(
        '/groups',
        data: {
          'name': name,
          if (photoUrl != null) 'photo_url': photoUrl,
          if (rules != null && rules.isNotEmpty) 'rules': rules,
          'member_ids': memberIds,
        },
      ),
    );
    return (
      group: GroupDetail.fromJson(data['group'] as Map<String, dynamic>),
      results: _results(data['results']),
    );
  }

  Future<List<GroupSummary>> mine() async {
    final data = await _call(() => _dio.get<dynamic>('/groups'));
    if (data is! List) throw _unexpected;
    return [
      for (final g in data) GroupSummary.fromJson(g as Map<String, dynamic>),
    ];
  }

  Future<GroupDetail> detail(String id) async =>
      GroupDetail.fromJson(await _map(() => _dio.get<dynamic>('/groups/$id')));

  /// Owner/admin only. An empty [rules] clears them.
  Future<GroupDetail> update(
    String id, {
    String? name,
    String? photoUrl,
    String? rules,
  }) async => GroupDetail.fromJson(
    await _map(
      () => _dio.put<dynamic>(
        '/groups/$id',
        data: {
          if (name != null) 'name': name,
          if (photoUrl != null) 'photo_url': photoUrl,
          if (rules != null) 'rules': rules,
        },
      ),
    ),
  );

  /// Adds people by user id (UID) and/or username.
  Future<List<AddResult>> addMembers(
    String id, {
    List<String> userIds = const [],
    List<String> usernames = const [],
  }) async {
    final data = await _map(
      () => _dio.post<dynamic>(
        '/groups/$id/members',
        data: {'user_ids': userIds, 'usernames': usernames},
      ),
    );
    return _results(data['results']);
  }

  Future<void> removeMember(String id, String userId) =>
      _call(() => _dio.delete<dynamic>('/groups/$id/members/$userId'));

  Future<void> setRole(String id, String userId, GroupRole role) => _call(
    () => _dio.put<dynamic>(
      '/groups/$id/members/$userId/role',
      data: {'role': role.name},
    ),
  );

  Future<void> transfer(String id, String userId) => _call(
    () => _dio.post<dynamic>('/groups/$id/transfer', data: {'user_id': userId}),
  );

  Future<void> leave(String id, {String? newOwnerId}) => _call(
    () => _dio.post<dynamic>(
      '/groups/$id/leave',
      data: {if (newOwnerId != null) 'new_owner_id': newOwnerId},
    ),
  );

  /// Messages after [after] (all you can see when null), oldest first, in the
  /// same shape as the socket's.
  Future<List<Map<String, dynamic>>> messagesSince(
    String id, {
    DateTime? after,
  }) async {
    final data = await _call(
      () => _dio.get<dynamic>(
        '/groups/$id/messages',
        queryParameters: {
          if (after != null) 'after': after.toUtc().toIso8601String(),
        },
      ),
    );
    if (data is! List) throw _unexpected;
    return [for (final m in data) m as Map<String, dynamic>];
  }

  static const _unexpected = ApiException(
    'The server sent an unexpected response.',
  );

  List<AddResult> _results(Object? raw) => [
    for (final r in (raw as List? ?? const []))
      AddResult.fromJson(r as Map<String, dynamic>),
  ];

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
