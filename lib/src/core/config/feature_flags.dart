/// Switches for features that are built but deliberately not offered yet.
class FeatureFlags {
  FeatureFlags._();

  /// Email + password sign-up and log-in on the landing page.
  ///
  /// Off for now: email addresses are not verified, so anyone could register
  /// as someone else's address. Google sign-in only accepts accounts Google
  /// has already verified. The screens, view models and backend support are
  /// all still in place — flip this to `true` once email confirmation is
  /// switched on in Supabase (Authentication → Providers → Email → "Confirm
  /// email").
  static const bool emailSignIn = false;
}
