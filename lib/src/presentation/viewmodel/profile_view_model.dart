import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/services/profile_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';

/// The signed-in user's profile, or null when they have not made one.
///
/// [AsyncNotifier] rather than [Notifier] because the initial value is fetched:
/// this gives the UI loading and error states for free via [AsyncValue].
///
/// Method names avoid `update`, `create`, and `future` — [AsyncNotifier]
/// already defines members with those names.
class ProfileViewModel extends AsyncNotifier<Profile?> {
  ProfileService get _profiles => ref.read(profileServiceProvider);

  @override
  Future<Profile?> build() async {
    // Keyed on the account id, not the auth status: status flips back to
    // `authenticated` when a *different* person signs in, which would leave
    // the previous account's profile on screen. Watching the id also avoids
    // refetching when an unrelated field such as `isBusy` toggles.
    final accountId = ref.watch(currentAccountIdProvider);

    if (accountId == null) return null;
    return _profiles.getMine();
  }

  /// `POST /profile/me`.
  ///
  /// Returns null on success, or a message to show the user. Mutations report
  /// failure this way instead of pushing an [AsyncError] into [state], because
  /// a rejected write ("username already taken") should leave the currently
  /// loaded profile on screen rather than replacing it with an error page.
  Future<String?> createProfile(ProfileCreateRequest request) {
    return _write(() => _profiles.create(request));
  }

  /// `PUT /profile/me`. Same contract as [createProfile].
  Future<String?> updateProfile(ProfileUpdateRequest request) {
    if (request.isEmpty) return Future.value(null);
    return _write(() => _profiles.update(request));
  }

  /// Re-reads `GET /profile/me`, showing a loading state while it runs.
  Future<void> reload() async {
    state = const AsyncValue<Profile?>.loading();
    state = await AsyncValue.guard(() => _profiles.getMine());
  }

  Future<String?> _write(Future<Profile> Function() action) async {
    try {
      state = AsyncValue<Profile?>.data(await action());
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }
}
