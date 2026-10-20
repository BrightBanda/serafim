import 'package:serafim/src/core/platform/google_support.dart';

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

  /// Whether to offer email sign-in on this device: when the flag is on, or
  /// when Google sign-in can't work here (Linux and Windows desktop), because
  /// otherwise nobody could sign in at all.
  static bool get emailSignInAvailable => emailSignIn || !googleSignInSupported;

  /// Circles, and the posts inside them.
  ///
  /// Off until the backend that serves them is deployed: the Circles tab
  /// would show nothing, and a tab that cannot do anything is worse than no
  /// tab. The screens are all in place — flip this to `true` once
  /// `POST /circles` answers on the deployed API, and the tab appears with
  /// its content behind it.
  ///
  /// The admin dashboard reserves a `FeatureFlags.circles` switch of its own
  /// (see `docs/admin-dashboard-README.md` §10.7); this is the app's half of
  /// the same idea.
  static const bool circles = true;

  /// Posts on a profile, and the feed that mixes them with the posts of
  /// people you follow. Needs the same backend as [circles].
  static const bool posts = true;
}
