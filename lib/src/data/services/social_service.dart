import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/public_user.dart';

/// Talks to the backend's friends, discover and user-search routes.
class SocialService {
  const SocialService(this._dio);

  final Dio _dio;

  Future<List<PublicUser>> discover({int limit = 100, int offset = 0}) async {
    final data = await _get('/discover', {'limit': limit, 'offset': offset});
    return _users(data);
  }

  Future<List<PublicUser>> friends() async => _users(await _get('/friends'));

  Future<FriendRequests> requests() async {
    final data = await _get('/friends/requests');
    if (data is! Map) {
      throw const ApiException('The server sent an unexpected response.');
    }
    return FriendRequests(
      incoming: _users(data['incoming']),
      outgoing: _users(data['outgoing']),
    );
  }

  /// Partial username or exact UID.
  Future<List<PublicUser>> search(String query) async =>
      _users(await _get('/users/search', {'q': query}));

  Future<PublicUser> user(String id) async {
    final data = await _get('/users/$id');
    if (data is! Map<String, dynamic>) {
      throw const ApiException('The server sent an unexpected response.');
    }
    return PublicUser.fromJson(data);
  }

  Future<FriendStatus> sendRequest(String userId) =>
      _mutate('POST', '/friends/requests', body: {'user_id': userId});

  Future<FriendStatus> accept(String userId) =>
      _mutate('POST', '/friends/requests/$userId/accept');

  Future<FriendStatus> reject(String userId) =>
      _mutate('POST', '/friends/requests/$userId/reject');

  /// Withdraws a request you sent.
  Future<FriendStatus> cancel(String userId) =>
      _mutate('DELETE', '/friends/requests/$userId');

  Future<FriendStatus> unfriend(String userId) =>
      _mutate('DELETE', '/friends/$userId');

  Future<List<PublicUser>> following() async =>
      _users(await _get('/follows/following'));

  Future<List<PublicUser>> followers() async =>
      _users(await _get('/follows/followers'));

  Future<void> follow(String userId) async {
    await _send('POST', '/follows/$userId');
  }

  Future<void> unfollow(String userId) async {
    await _send('DELETE', '/follows/$userId');
  }

  Future<void> _send(String method, String path) async {
    try {
      await _dio.request<dynamic>(path, options: Options(method: method));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  List<PublicUser> _users(Object? data) {
    if (data is! List) {
      throw const ApiException('The server sent an unexpected response.');
    }
    // Keyed by id so a refresh that overlaps with an earlier page can never
    // show the same person twice.
    final byId = <String, PublicUser>{};
    for (final json in data) {
      final user = PublicUser.fromJson(json as Map<String, dynamic>);
      byId[user.id] = user;
    }
    return byId.values.toList(growable: false);
  }

  Future<Object?> _get(String path, [Map<String, dynamic>? query]) async {
    try {
      final response = await _dio.get<dynamic>(path, queryParameters: query);
      return response.data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<FriendStatus> _mutate(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: body,
        options: Options(method: method),
      );
      final data = response.data;
      return FriendStatus.parse(
        data is Map ? data['friend_status'] as String? : null,
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
