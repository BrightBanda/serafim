import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Whether "Continue with Google" can work on this platform.
///
/// The Google sign-in plugin only has implementations for Android, iOS, macOS
/// and the web. On Linux and Windows desktop there is nothing to call, so the
/// app hides the button there and offers email sign-in instead.
bool get googleSignInSupported {
  if (kIsWeb) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };
}
