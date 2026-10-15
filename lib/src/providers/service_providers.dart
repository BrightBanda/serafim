import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/data/services/avatar_storage_service.dart';
import 'package:serafim/src/data/services/chat_media_store.dart';
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
