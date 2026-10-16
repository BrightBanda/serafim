import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/data/services/attachment_download_service.dart';
import 'package:serafim/src/data/services/avatar_storage_service.dart';
import 'package:serafim/src/data/services/chat_media_store.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/data/services/profile_service.dart';
import 'package:serafim/src/data/services/user_service.dart';
import 'package:serafim/src/providers/network_providers.dart';

/// Supabase auth. Built on the *unauthenticated* client — see
/// [supabaseDioProvider] for why.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseDioProvider));
});

/// Backend `/auth` routes. Built on the authenticated client.
final userServiceProvider = Provider<UserService>((ref) {
  return UserService(ref.watch(apiDioProvider));
});

/// Backend `/profile` routes. Built on the authenticated client.
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ref.watch(apiDioProvider));
});

/// Profile pictures → Supabase Storage `avatars` bucket.
final avatarStorageServiceProvider = Provider<AvatarStorageService>((ref) {
  return AvatarStorageService(
    ref.watch(storageDioProvider),
    ref.watch(appConfigProvider).supabaseUrl,
  );
});

/// Chat image files kept on the device.
final chatMediaStoreProvider = Provider<ChatMediaStore>(
  (ref) => const ChatMediaStore(),
);

/// Exports chat images to the gallery / Downloads folder.
final attachmentDownloadServiceProvider = Provider<AttachmentDownloadService>(
  (ref) => const AttachmentDownloadService(),
);

/// Google account picker → ID token.
final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  final config = ref.watch(appConfigProvider);
  return GoogleAuthService(
    webClientId: config.googleWebClientId,
    iosClientId: config.googleIosClientId,
  );
});
