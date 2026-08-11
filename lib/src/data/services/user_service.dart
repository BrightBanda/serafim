import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_user.dart';

/// Talks to the Serafim backend's `/auth` routes.
///
/// Note what is missing: no sign-up, no login, no password. Those live in
/// [AuthService] against Supabase. This service only deals with the
/// application-side user row that hangs off the verified token.
class UserService {
  const UserService(this._dio);

  final Dio _dio;

  /// `POST /auth/sync` — creates or refreshes our user row for the caller.
  ///
  /// Idempotent on the server (a Postgres upsert), so it is safe to call on
  /// every launch and after every sign-in.
  Future<AppUser> sync() => _get('/auth/sync', method: 'POST');

  /// `GET /auth/me` — the user plus their profile, if they have one.
  Future<AppUser> me() => _get('/auth/me');

  Future<AppUser> _get(String path, {String method = 'GET'}) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        options: Options(method: method),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('The server sent an unexpected response.');
      }
      return AppUser.fromJson(data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
