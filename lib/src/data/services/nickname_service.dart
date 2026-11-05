import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// The nicknames you've given your friends (user id → nickname), and the
/// ones they've given you.
class Nicknames {
  const Nicknames({this.given = const {}, this.received = const {}});

  /// What you call each friend.
  final Map<String, String> given;

  /// What each friend calls you.
  final Map<String, String> received;

  factory Nicknames.fromJson(Map<String, dynamic> json) {
    Map<String, String> read(Object? list) => {
      for (final e in (list as List? ?? const []))
        if (e is Map) e['user_id'].toString(): e['nickname'].toString(),
    };
    return Nicknames(
      given: read(json['given']),
      received: read(json['received']),
    );
  }
}

/// Talks to the backend's `/nicknames` routes. Only friends can be given a
/// nickname; the server checks.
class NicknameService {
  const NicknameService(this._dio);

  final Dio _dio;

  Future<Nicknames> get() async =>
      Nicknames.fromJson(await _map(() => _dio.get<dynamic>('/nicknames')));

  /// Sets what you call [userId]; an empty [nickname] removes it.
  Future<Nicknames> set(String userId, String nickname) async =>
      Nicknames.fromJson(
        await _map(
          () => _dio.put<dynamic>(
            '/nicknames/$userId',
            data: {'nickname': nickname},
          ),
        ),
      );

  Future<Map<String, dynamic>> _map(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final data = (await request()).data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Something went wrong. Please try again.');
      }
      return data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
