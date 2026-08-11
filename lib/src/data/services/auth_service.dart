import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/auth_session.dart';

/// Result of a sign-up attempt.
///
/// Supabase returns a session immediately when email confirmation is off, and
/// a user record with no tokens when it is on. The caller has to handle both,
/// so the difference is modelled explicitly instead of returning a nullable
/// session and hoping the view model remembers why.
class SignUpResult {
  const SignUpResult.signedIn(AuthSession this.session) : needsEmailConfirmation = false;
  const SignUpResult.awaitingConfirmation()
    : session = null,
      needsEmailConfirmation = true;

  final AuthSession? session;
  final bool needsEmailConfirmation;
}

/// Talks to Supabase GoTrue over dio.
///
/// This is the *only* place credentials are handled. The Serafim backend never
/// sees a password — it only ever verifies the access token this service
/// obtains. Its dio instance deliberately has no auth interceptor: the
/// interceptor calls [refresh] to recover from a 401, and wiring it here would
/// make that recursive.
class AuthService {
  const AuthService(this._dio);

  final Dio _dio;

  /// `POST /auth/v1/signup`
  Future<SignUpResult> signUp({required String email, required String password}) async {
    final json = await _post('/signup', {'email': email, 'password': password});

    // No access_token means the project requires email confirmation.
    if (json['access_token'] == null) {
      return const SignUpResult.awaitingConfirmation();
    }
    return SignUpResult.signedIn(AuthSession.fromJson(json));
  }

  /// `POST /auth/v1/token?grant_type=password`
  Future<AuthSession> signIn({required String email, required String password}) async {
    final json = await _post(
      '/token',
      {'email': email, 'password': password},
      query: {'grant_type': 'password'},
    );
    return AuthSession.fromJson(json);
  }

  /// `POST /auth/v1/token?grant_type=refresh_token`
  ///
  /// Supabase rotates the refresh token on every use, so the returned session
  /// must replace the stored one wholesale.
  Future<AuthSession> refresh(String refreshToken) async {
    final json = await _post(
      '/token',
      {'refresh_token': refreshToken},
      query: {'grant_type': 'refresh_token'},
    );
    return AuthSession.fromJson(json);
  }

  /// `POST /auth/v1/logout` — revokes the refresh token server-side.
  ///
  /// Best-effort: a failure here must not stop the client from clearing local
  /// state, so the caller is expected to discard the session either way.
  Future<void> signOut(String accessToken) async {
    try {
      await _dio.post<dynamic>(
        '/logout',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on DioException {
      // Token may already be expired or revoked; nothing to recover.
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        path,
        data: body,
        queryParameters: query,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('The authentication server sent an unexpected response.');
      }
      return data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    } on FormatException catch (error) {
      throw ApiException(error.message);
    }
  }
}
