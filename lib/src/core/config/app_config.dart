/// Compile-time configuration.
///
/// Nothing here is read from a bundled file: values arrive via `--dart-define`
/// so no key ever lands in source control. The Supabase publishable key is
/// safe to ship in a client binary (it only grants what row-level security
/// allows), but it still does not belong in git.
///
/// Run with:
/// ```
/// flutter run --dart-define-from-file=.env
/// ```
/// or pass the values individually:
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_... \
///   --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// ```
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.apiBaseUrl,
  });

  /// Reads the values baked in at build time.
  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      apiBaseUrl: String.fromEnvironment(
        'API_BASE_URL',
        // Android emulators reach the host machine on 10.0.2.2, never on
        // localhost. Override this define for a device or a deployed API.
        defaultValue: 'http://10.0.2.2:8000',
      ),
    );
  }

  /// Supabase project URL, e.g. `https://abcdefgh.supabase.co`.
  final String supabaseUrl;

  /// Supabase publishable key (`sb_publishable_...`), sent as the `apikey`
  /// header. This replaced the legacy `anon` JWT; projects created before the
  /// change can still use that instead, from the dashboard's
  /// "Legacy anon, service_role API keys" tab.
  ///
  /// Never the `sb_secret_...` key — that one bypasses row-level security and
  /// belongs only on a server.
  final String supabasePublishableKey;

  /// Base URL of the Serafim FastAPI backend.
  final String apiBaseUrl;

  /// GoTrue lives under `/auth/v1` on the project URL.
  String get supabaseAuthUrl => '${supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/v1';

  bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Human-readable reason the app cannot start, or null when all is well.
  String? get configurationError {
    if (supabaseUrl.isEmpty) return 'SUPABASE_URL is not set.';
    if (supabasePublishableKey.isEmpty) {
      return 'SUPABASE_PUBLISHABLE_KEY is not set.';
    }
    if (apiBaseUrl.isEmpty) return 'API_BASE_URL is not set.';
    return null;
  }
}
