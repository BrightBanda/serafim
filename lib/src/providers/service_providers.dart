import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/auth_service.dart';
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
