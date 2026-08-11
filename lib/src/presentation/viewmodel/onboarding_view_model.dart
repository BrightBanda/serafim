import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    this.interests = const {},
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final OnboardingStep step;
  final String displayName;
  final Set<String> interests;
  final bool isSubmitting;
  final String? errorMessage;

  /// True once a profile exists, or the user skipped past setup. Lets the
  /// gate move on without re-prompting for the rest of the session.
  final bool completed;

  OnboardingState copyWith({
    OnboardingStep? step,
    String? displayName,
    Set<String>? interests,
    bool? isSubmitting,
    Object? errorMessage = _unset,
    bool? completed,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      displayName: displayName ?? this.displayName,
      interests: interests ?? this.interests,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      completed: completed ?? this.completed,
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
  void continueToInterests(String displayName) {
    state = state.copyWith(
      displayName: displayName.trim(),
      step: OnboardingStep.interests,
      errorMessage: null,
    );
  }

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
    );

    final email = ref.read(currentUserProvider)?.email;
    final displayName = _resolveDisplayName(email);

    if (displayName == null) {
      // No name and no email to derive one from — a phone-only account. The
      // backend requires display_name, so let them into the app and collect
      // it later rather than blocking on a screen they cannot satisfy.
      state = state.copyWith(isSubmitting: false, completed: true);
      return;
    }

    final profiles = ref.read(profileViewModelProvider.notifier);
    final request = ProfileCreateRequest(
      displayName: displayName,
      username: _slugify(displayName),
      interests: interests.isEmpty ? null : interests.toList(),
    );

    var error = await profiles.createProfile(request);

    // Usernames are derived, not chosen, so a collision is our problem to
    // solve rather than something to show the user. Retry once with the
    // account id mixed in, which cannot collide with another account.
    if (error != null && _isUsernameTaken(error)) {
      error = await profiles.createProfile(
        ProfileCreateRequest(
          displayName: displayName,
          username: '${_slugify(displayName)}_${_accountSuffix()}',
          interests: interests.isEmpty ? null : interests.toList(),
        ),
      );
    }

    if (!ref.mounted) return;

    state = error == null
        ? state.copyWith(isSubmitting: false, completed: true)
        : state.copyWith(isSubmitting: false, errorMessage: error);
  }

  /// The typed name, else the email local-part, else null.
  String? _resolveDisplayName(String? email) {
    if (state.displayName.isNotEmpty) return state.displayName;

    final localPart = email?.split('@').first.trim();
    if (localPart != null && localPart.isNotEmpty) return localPart;

    return null;
  }

  String _accountSuffix() {
    final id = ref.read(currentUserProvider)?.id ?? '';
    return id.length >= 4 ? id.substring(0, 4) : '1';
  }

  static bool _isUsernameTaken(String error) =>
      error.toLowerCase().contains('username already taken');

  /// Builds a username from a display name: lowercase, non-alphanumerics
  /// collapsed to underscores, trimmed to the column's 50-char limit.
  static String _slugify(String input) {
    final slug = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (slug.isEmpty) return 'user';
    return slug.length > 40 ? slug.substring(0, 40) : slug;
  }
}
