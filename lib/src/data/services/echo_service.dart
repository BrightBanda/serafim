import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/echo.dart';

/// Talks to the backend's `/echos` routes. Every limit (a few a day, a
/// pause between them, a few received a day) is the server's; the app
/// only explains.
class EchoService {
  const EchoService(this._dio);

  final Dio _dio;

  Future<MyEchoStatus> mine() async =>
      MyEchoStatus.fromJson(await _map(() => _dio.get<dynamic>('/echos/mine')));

  /// Broadcasts an Echo; the answer says how many people it reached.
  Future<Echo> send({
    required String text,
    EchoAudience audience = EchoAudience.everyone,
    String? tag,
  }) async => Echo.fromJson(
    await _map(
      () => _dio.post<dynamic>(
        '/echos',
        data: {'text': text, 'audience': audience.name, 'tag': ?tag},
      ),
    ),
  );

  /// The latest Echo [userId] sent you (what an Echo notification opens).
  Future<Echo> latestFrom(String userId) async =>
      Echo.fromJson(await _map(() => _dio.get<dynamic>('/echos/from/$userId')));

  Future<void> close(String id) =>
      _call(() => _dio.delete<dynamic>('/echos/$id'));

  /// Answers an Echo; returns who to open a chat with.
  Future<String> respond(String id) async {
    final data = await _map(() => _dio.post<dynamic>('/echos/$id/respond'));
    return data['user_id'].toString();
  }

  Future<void> hide(String userId) =>
      _call(() => _dio.post<dynamic>('/echos/hide/$userId'));

  static const _unexpected = ApiException(
    'Something went wrong. Please try again.',
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
