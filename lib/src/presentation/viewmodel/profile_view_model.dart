import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/services/profile_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

/// The signed-in user's profile, or null when they have not made one.
///
/// [AsyncNotifier] rather than [Notifier] because the initial value is fetched:
/// this gives the UI loading and error states for free via [AsyncValue].
///
/// Method names avoid `update`, `create`, and `future` — [AsyncNotifier]
/// already defines members with those names.
class ProfileViewModel extends AsyncNotifier<Profile?> {
  ProfileService get _profiles => ref.read(profileServiceProvider);

  // Not `async`: with a saved profile this returns it directly, so the state
  // is data on the first read and the app opens straight onto its screens
  // instead of flashing the splash for a frame.
  @override
  FutureOr<Profile?> build() {
    // Keyed on the account id, not the auth status: status flips back to
    // `authenticated` when a *different* person signs in, which would leave
    // the previous account's profile on screen. Watching the id also avoids
    // refetching when an unrelated field such as `isBusy` toggles.
    final accountId = ref.watch(currentAccountIdProvider);
    if (accountId == null) return null;

    final cache = ref.read(localCacheProvider);

    // A saved copy exists from the last time the app was open: show it right
    // away and check the server behind it, rather than making startup wait.
    final saved = cache.profile(accountId);
    if (saved != null) {
      Future.microtask(() => _revalidate(accountId));
      return saved.profile;
    }

    return _loadFirstTime(accountId);
  }

  Future<Profile?> _loadFirstTime(String accountId) async {
    final fresh = await _profiles.getMine().timeout(loadTimeout);
    await ref.read(localCacheProvider).saveProfile(accountId, fresh);
    return fresh;
  }

  /// Longer than this with nothing to show and the retry screen takes over,
  /// instead of a spinner that never ends.
  @visibleForTesting
  static Duration loadTimeout = const Duration(seconds: 25);

  /// Refreshes the saved profile in the background. If the server cannot be
  /// reached, the saved copy stays on screen: offline is not an error.
  Future<void> _revalidate(String accountId) async {
    try {
      final fresh = await _profiles.getMine().timeout(loadTimeout);
      if (!ref.mounted || ref.read(currentAccountIdProvider) != accountId)
        return;
      await ref.read(localCacheProvider).saveProfile(accountId, fresh);
      state = AsyncValue<Profile?>.data(fresh);
    } catch (_) {
      // Keep what is on screen.
    }
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

  /// Uploads [jpegBytes] to the avatars bucket and saves the URL on the
  /// profile. Same contract as [createProfile]: null on success, else a
  /// message to show.
  Future<String?> uploadAvatar(Uint8List jpegBytes) async {
    final accountId = ref.read(currentAccountIdProvider);
    if (accountId == null) return 'You are signed out.';
    try {
      final url = await ref
          .read(avatarStorageServiceProvider)
          .uploadAvatar(accountId, jpegBytes);
      return await updateProfile(ProfileUpdateRequest(profilePic: url));
    } catch (error) {
      return humanError(error, fallback: "Couldn't upload your photo.");
    }
  }

  /// Re-reads `GET /profile/me`, showing a loading state while it runs.
  Future<void> reload() async {
    state = const AsyncValue<Profile?>.loading();
    state = await AsyncValue.guard(() => _profiles.getMine());
  }

  Future<String?> _write(Future<Profile> Function() action) async {
    try {
      final saved = await action();
      state = AsyncValue<Profile?>.data(saved);
      final account = ref.read(currentAccountIdProvider);
      if (account != null)
        await ref.read(localCacheProvider).saveProfile(account, saved);
      return null;
    } catch (error) {
      return humanError(error);
    }
  }
}
