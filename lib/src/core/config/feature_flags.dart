import 'package:serafim/src/core/platform/google_support.dart';

/// Switches for features that are built but deliberately not offered yet.
class FeatureFlags {
  FeatureFlags._();

  /// Email + password sign-up and log-in on the landing page, below Google.
  ///
  /// On now that email addresses are confirmed with a one-time code (the
  /// "Confirm email" switch is on in Supabase, and its "Confirm signup" email
  /// template carries the code): nobody can register as someone else's
  /// address. Turn it off to offer Google only.
  static const bool emailSignIn = true;

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

  /// Moments: a photo or video that lasts 24 hours, with a coloured ring round
  /// the picture of whoever has one. Needs the backend's `/moments` routes
  /// (`sql/030_moments.sql` run, backend deployed); without them the rings
  /// simply never appear and posting says it can't be done right now.
  static const bool moments = true;
}
