import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/public_user.dart';

/// Talks to the backend's `/wings` routes. Every call returns your Wings as
/// they stand afterwards.
class WingsService {
  const WingsService(this._dio);

  final Dio _dio;

  Future<List<PublicUser>> list() => _call('GET', '/wings');

  /// Names a friend as a Wing. Fails with 409 when there are already six.
  Future<List<PublicUser>> add(String userId) => _call('PUT', '/wings/$userId');

  Future<List<PublicUser>> remove(String userId) =>
      _call('DELETE', '/wings/$userId');

  Future<List<PublicUser>> _call(String method, String path) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        options: Options(method: method),
      );
      final data = response.data;
      if (data is! List) {
        throw const ApiException('Something went wrong. Please try again.');
      }
      return [
        for (final e in data) PublicUser.fromJson(e as Map<String, dynamic>),
      ];
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
