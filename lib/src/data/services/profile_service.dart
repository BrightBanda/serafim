import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/profile.dart';

/// Talks to the Serafim backend's `/profile` routes.
///
/// The caller's identity always comes from the bearer token attached by
/// [AuthInterceptor] — no method here takes a user id, which is what keeps a
/// client from asking for someone else's private data by guessing an id.
class ProfileService {
  const ProfileService(this._dio);

  final Dio _dio;

  /// `GET /profile/me` — returns null when the user has not created one yet.
  ///
  /// The backend answers 404 in that case, which is an expected state rather
  /// than a failure, so it is folded into a null instead of an exception.
  Future<Profile?> getMine() async {
    try {
      return await _request('GET', '/profile/me');
    } on ApiException catch (error) {
      if (error.isNotFound) return null;
      rethrow;
    }
  }

  /// `POST /profile/me`
  Future<Profile> create(ProfileCreateRequest request) =>
      _request('POST', '/profile/me', body: request.toJson());

  /// `PUT /profile/me`
  Future<Profile> update(ProfileUpdateRequest request) =>
      _request('PUT', '/profile/me', body: request.toJson());

  /// `PUT /profile/me/halo`: lights your Halo for [minutes]. Returns when it
  /// will go out. [wingsOnly] limits who sees it to your Wings.
  Future<DateTime> lightHalo(int minutes, {bool wingsOnly = false}) async {
    final until = await _halo(
      'PUT',
      body: {'minutes': minutes, 'audience': wingsOnly ? 'wings' : 'friends'},
    );
    if (until == null) {
      throw const ApiException('The server sent an unexpected response.');
    }
    return until;
  }

  /// `DELETE /profile/me/halo`: puts it out.
  Future<void> dimHalo() async {
    await _halo('DELETE');
  }

  Future<DateTime?> _halo(String method, {Map<String, dynamic>? body}) async {
    try {
      final response = await _dio.request<dynamic>(
        '/profile/me/halo',
        data: body,
        options: Options(method: method),
      );
      final data = response.data;
      final until = data is Map<String, dynamic> ? data['halo_until'] : null;
      return until is String ? DateTime.tryParse(until)?.toUtc() : null;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Profile> _request(
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
      if (data is! Map<String, dynamic>) {
        throw const ApiException('The server sent an unexpected response.');
      }
      return Profile.fromJson(data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
