import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/config/profile_limits.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';

/// Sentinel so [OnboardingState.copyWith] can tell "leave the error alone"
/// from "clear the error".
const Object _unset = Object();

enum OnboardingStep { photoName, interests }

/// State carried across the two onboarding screens.
///
/// It lives here rather than in either page because the answers have to
/// survive stepping forward and back, and because both are submitted in a
/// single `POST /profile/me` at the end.
class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.photoName,
    this.displayName = '',
    this.username = '',
    this.interests = const {},
    this.isSubmitting = false,
    this.errorMessage,
    this.usernameError,
    this.completed = false,
    this.avatarBytes,
  });

  final OnboardingStep step;
  final String displayName;
  final String username;
  final Set<String> interests;
  final bool isSubmitting;
  final String? errorMessage;
  final String? usernameError;

  /// True once a profile exists, or the user skipped past setup. Lets the
  /// gate move on without re-prompting for the rest of the session.
  final bool completed;

  /// Photo picked in step 2 (already shrunk). Uploaded once the profile
  /// exists, since the avatar URL is stored on it.
  final Uint8List? avatarBytes;

  OnboardingState copyWith({
    OnboardingStep? step,
    String? displayName,
    String? username,
    Set<String>? interests,
    bool? isSubmitting,
    Object? errorMessage = _unset,
    Object? usernameError = _unset,
    bool? completed,
    Uint8List? avatarBytes,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      interests: interests ?? this.interests,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      usernameError: identical(usernameError, _unset)
          ? this.usernameError
          : usernameError as String?,
      completed: completed ?? this.completed,
      avatarBytes: avatarBytes ?? this.avatarBytes,
    );
  }
}

/// Drives the two-step profile setup that runs straight after sign-up.
///
/// The pages stay presentational: they report what the user did, this decides
/// what it means and when to call the backend.
class OnboardingViewModel extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    // Watching the account id resets the whole flow whenever a different
    // person signs in. Without this, `completed` from the first sign-up
    // survives a sign-out and the next account skips setup entirely.
    ref.watch(currentAccountIdProvider);
    return const OnboardingState();
  }

  /// Step 2 → step 3. An empty name is allowed here; skipping is a valid
  /// path and [finish] falls back to the email local-part.
  void continueToInterests(String displayName, {String username = ''}) {
    state = state.copyWith(
      displayName: displayName.trim(),
      username: username.trim().toLowerCase(),
      step: OnboardingStep.interests,
      errorMessage: null,
      usernameError: null,
    );
  }

  void usernameChanged(String value) {
    state = state.copyWith(
      username: value.trim().toLowerCase(),
      usernameError: null,
    );
  }

  void setAvatar(Uint8List bytes) => state = state.copyWith(avatarBytes: bytes);

  void backToPhotoName() {
    state = state.copyWith(step: OnboardingStep.photoName, errorMessage: null);
  }

  void dismissError() => state = state.copyWith(errorMessage: null);

  /// Creates the profile from everything gathered across both steps.
  ///
  /// Called by both "Finish setup" and "skip this step" — skipping just means
  /// an empty interest set, not abandoning the profile.
  Future<void> finish(Set<String> interests) async {
    if (state.isSubmitting) return;

    state = state.copyWith(
      interests: interests,
      isSubmitting: true,
      errorMessage: null,
      usernameError: null,
    );

    final email = ref.read(currentUserProvider)?.email;
    final resolved = _resolveDisplayName(email);
    // The server caps display names; an email local-part can be longer.
    final displayName =
        resolved == null || resolved.length <= ProfileLimits.displayNameMax
        ? resolved
        : resolved.substring(0, ProfileLimits.displayNameMax).trim();

    if (displayName == null) {
      // No name and no email to derive one from — a phone-only account. The
      // backend requires display_name, so let them into the app and collect
      // it later rather than blocking on a screen they cannot satisfy.
      state = state.copyWith(isSubmitting: false, completed: true);
      return;
    }

    final profiles = ref.read(profileViewModelProvider.notifier);
    final username = state.username.isNotEmpty
        ? state.username
        : _slugify(displayName);
    final usernameError = ProfileLimits.usernameError(username);
    if (usernameError != null) {
      state = state.copyWith(isSubmitting: false, usernameError: usernameError);
      return;
    }

    final request = ProfileCreateRequest(
      displayName: displayName,
      username: username,
      interests: interests.isEmpty ? null : interests.toList(),
    );

    final error = await profiles.createProfile(request);

    // The picture is a nicety: if the upload fails the account is still
    // fully set up, and they can retry from the profile page.
    final avatar = state.avatarBytes;
    if (error == null && avatar != null) {
      await profiles.uploadAvatar(avatar);
    }

    if (!ref.mounted) return;

    if (error == null) {
      state = state.copyWith(isSubmitting: false, completed: true);
    } else if (_isUsernameTaken(error)) {
      state = state.copyWith(
        isSubmitting: false,
        usernameError: error,
        step: OnboardingStep.photoName,
      );
    } else {
      state = state.copyWith(isSubmitting: false, errorMessage: error);
    }
  }

  /// The typed name, else the email local-part, else null.
  String? _resolveDisplayName(String? email) {
    if (state.displayName.isNotEmpty) return state.displayName;

    final localPart = email?.split('@').first.trim();
    if (localPart != null && localPart.isNotEmpty) return localPart;

    return null;
  }

  /// A username the server accepts, with room left for the `_xxxx` suffix
  /// added on a collision.
  static String _slugify(String input) {
    var slug = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (slug.isEmpty) return 'user';
    if (slug.length < ProfileLimits.usernameMin) slug = '${slug}_user';
    const room = ProfileLimits.usernameMax - 5; // "_" + 4-character suffix.
    if (slug.length > room) {
      slug = slug.substring(0, room).replaceAll(RegExp(r'_+$'), '');
    }
    return slug;
  }

  static bool _isUsernameTaken(String error) {
    final message = error.toLowerCase();
    return message.contains('username') &&
        (message.contains('already taken') ||
            message.contains('already exists') ||
            message.contains('in use'));
  }
}
