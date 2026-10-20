import 'package:google_sign_in/google_sign_in.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/core/platform/google_support.dart';

/// The user closed the Google account picker. Not an error worth showing.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// Talks to the Google account picker and returns an ID token. What to do with
/// the token (exchange it with Supabase) is [AuthService]'s job — Firebase Auth
/// is intentionally not involved, so there is exactly one source of truth for
/// who is signed in.
class GoogleAuthService {
  GoogleAuthService({required this.webClientId, this.iosClientId = ''});

  final String webClientId;
  final String iosClientId;

  Future<void>? _initialised;

  Future<void> _init() {
    return _initialised ??= GoogleSignIn.instance.initialize(
      // The *web* client id makes Google mint an ID token whose audience
      // Supabase accepts, even when signing in from an Android/iOS app.
      serverClientId: webClientId,
      clientId: iosClientId.isEmpty ? null : iosClientId,
    );
  }

  /// Shows the account picker and returns the ID token.
  ///
  /// Throws [GoogleSignInCancelled] if the user backs out and [ApiException]
  /// for anything else, with a message fit for the screen.
  Future<String> signIn() async {
    if (!googleSignInSupported) {
      throw const ApiException(
        "Google sign-in isn't available on this device. Use email instead.",
      );
    }
    if (webClientId.isEmpty) {
      throw const ApiException(
        'Google sign-in is not set up yet. Add GOOGLE_WEB_CLIENT_ID to the '
        'app configuration and rebuild.',
      );
    }

    try {
      await _init();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const ApiException(
          'Google sign-in is not supported on this platform.',
        );
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException(
          'Google did not return an identity token. Please try again.',
        );
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      throw switch (e.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted => const GoogleSignInCancelled(),
        GoogleSignInExceptionCode.clientConfigurationError =>
          const ApiException(
            'Google sign-in is misconfigured (check the SHA-1 fingerprint and '
            'client ids in the Firebase project).',
          ),
        _ => ApiException(
          'Google sign-in failed. ${e.description ?? ''}'.trim(),
        ),
      };
    }
  }

  /// An access token for the app's private folder in the person's Google
  /// Drive (`drive.appdata`): files there are visible only to this app, so no
  /// broad Drive access is asked for. Used by the backup feature.
  Future<String> driveAccessToken() async {
    if (!googleSignInSupported) {
      throw const ApiException(
        "Google Drive backup isn't available on this device. Use Export "
        'instead.',
      );
    }
    try {
      await _init();
      final instance = GoogleSignIn.instance;
      final account =
          await instance.attemptLightweightAuthentication() ??
          await instance.authenticate();
      final auth = await account.authorizationClient.authorizeScopes(const [
        'https://www.googleapis.com/auth/drive.appdata',
      ]);
      return auth.accessToken;
    } on GoogleSignInException catch (e) {
      throw switch (e.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted => const GoogleSignInCancelled(),
        _ => ApiException(
          'Could not reach Google Drive. ${e.description ?? ''}'.trim(),
        ),
      };
    }
  }

  /// Forgets the chosen account so the picker appears next time.
  Future<void> signOut() async {
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to clean up if it never started.
    }
  }
}
