/// Length limits for profile fields. The backend enforces the same numbers
/// (app/schemas/profile.py); these drive the counters and checks in the app so
/// people find out before saving.
class ProfileLimits {
  ProfileLimits._();

  static const usernameMin = 3;
  static const usernameMax = 20;
  static const displayNameMax = 30;
  static const bioMax = 160;

  static final usernamePattern = RegExp(
    '^[a-z0-9_]{$usernameMin,$usernameMax}\$',
  );

  /// Null when [name] (already trimmed) is acceptable, else what is wrong.
  static String? displayNameError(String name) {
    if (name.isEmpty) return 'Display name cannot be empty.';
    if (name.length > displayNameMax) {
      return 'Display name can be at most $displayNameMax characters.';
    }
    return null;
  }

  static String? usernameError(String username) {
    if (!usernamePattern.hasMatch(username)) {
      return 'Username must be $usernameMin–$usernameMax characters: '
          'lowercase letters, numbers and _.';
    }
    return null;
  }

  static String? bioError(String bio) {
    if (bio.length > bioMax) return 'Bio can be at most $bioMax characters.';
    return null;
  }
}
