import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:serafim/src/core/config/app_config.dart';
import 'package:serafim/src/data/services/session_store.dart';

/// Build-time configuration. Overridden in tests and in `main()` if you ever
/// need to point at a different environment without recompiling.
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

/// Platform keystore/keychain handle.
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

/// Holds the live session. Kept alive for the whole app: disposing it would
/// drop the in-memory token and log the user out mid-session.
final sessionStoreProvider = Provider<SessionStore>((ref) {
  final store = SessionStore(ref.watch(secureStorageProvider));
  ref.onDispose(store.dispose);
  return store;
});
