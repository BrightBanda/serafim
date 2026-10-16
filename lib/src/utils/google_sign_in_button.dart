import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/platform/google_support.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/utils/google_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// "Continue with Google", wired up: opens the Google account picker, trades
/// the result for a Supabase session, and lets [AuthGate] move on. Cancelling
/// the picker is silent; real failures show a message.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key});

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _working = false;

  Future<void> _signIn() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await ref.read(authViewModelProvider.notifier).signInWithGoogle();
      // Success: the auth gate swaps this screen out by itself.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(humanError(error)),
            backgroundColor: AppColors.rust,
          ),
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!googleSignInSupported) return const SizedBox.shrink();
    return GoogleButton(
      label: _working ? 'Signing in…' : 'Continue with Google',
      onPressed: _working ? null : _signIn,
    );
  }
}
