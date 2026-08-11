import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/service_providers.dart';

/// The signed-in user's own profile. Rebuilds itself when auth status changes,
/// because [ProfileViewModel.build] watches it.
final profileViewModelProvider =
    AsyncNotifierProvider<ProfileViewModel, Profile?>(ProfileViewModel.new);

/// True once we know the user is signed in but has no profile yet — the cue to
/// send them through profile creation.
final needsProfileSetupProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileViewModelProvider);
  return profile.hasValue && profile.value == null;
});

/// Someone else's profile, by username.
///
/// A read-only lookup with no commands attached, so it is a plain
/// [FutureProvider] rather than a view model. A family, so each username is
/// cached separately; auto-disposed, so a browsed profile does not linger in
/// memory after the screen closes.
final profileByUsernameProvider = FutureProvider.autoDispose
    .family<Profile, String>((ref, username) {
      return ref.watch(profileServiceProvider).getByUsername(username);
    });
