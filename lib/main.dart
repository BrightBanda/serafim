import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/onboarding_flow.dart';
import 'package:serafim/src/presentation/view/signup_page.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/onboarding_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/serafim_button.dart';

void main() {
  // ProviderScope holds every provider's state. Everything below it can reach
  // the config, dio clients, services, and view models.
  runApp(const ProviderScope(child: SerafimApp()));
}

class SerafimApp extends StatelessWidget {
  const SerafimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serafim',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.paper,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Chooses the screen from [AuthStatus].
///
/// This is the one place that reacts to sign-in and sign-out, which is why no
/// screen below it needs to navigate on an auth change — the gate swaps them.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A missing --dart-define is a build mistake, not a runtime state; fail
    // loudly rather than firing requests at an empty base URL.
    final configError = ref.watch(appConfigProvider).configurationError;
    if (configError != null) {
      return _Message(title: 'Not configured', body: configError);
    }

    final status = ref.watch(authStatusProvider);

    return switch (status) {
      // Still reading the keystore.
      AuthStatus.unknown => const _Splash(),
      AuthStatus.unauthenticated => const SignupScreen(),
      AuthStatus.awaitingEmailConfirmation => const _Message(
        title: 'Check your email',
        body:
            'We sent you a confirmation link. Open it, then come back and log in.',
      ),
      // Signed in with Supabase, but our own API is down. Offer a retry rather
      // than sending them back to sign-up, which would only produce a
      // "user already registered" error.
      AuthStatus.backendUnavailable => _Message(
        title: 'Server unreachable',
        body:
            "You're signed in, but the Serafim backend at "
            '${ref.watch(appConfigProvider).apiBaseUrl} did not respond. '
            'Start it, then retry.',
        onRetry: ref.read(authViewModelProvider.notifier).retryBackendSync,
        isRetrying: ref.watch(authViewModelProvider).isBusy,
      ),
      AuthStatus.authenticated => const _AuthedApp(),
    };
  }
}

/// Everything behind a valid session.
///
/// Profile setup is gated here rather than pushed from the sign-up screen, so
/// it also catches someone who signed up, closed the app mid-setup, and came
/// back — they land straight back in the flow instead of an empty home.
class _AuthedApp extends ConsumerWidget {
  const _AuthedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewModelProvider);
    final onboarding = ref.watch(onboardingViewModelProvider);

    return profile.when(
      loading: () => const _Splash(),
      error: (error, _) => _Message(
        title: 'Could not load your profile',
        body: '$error',
        onRetry: ref.read(profileViewModelProvider.notifier).reload,
      ),
      data: (profile) {
        // A profile exists, or they opted out of building one this session.
        if (profile != null || onboarding.completed) return const _Home();
        return const OnboardingFlow();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}

/// Placeholder for the signed-in app.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final auth = ref.watch(authViewModelProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Signed in', style: AppTextStyles.displayHeading),
              const SizedBox(height: 8),
              Text(
                user?.email ?? 'no email on file',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: auth.isBusy
                    ? null
                    : () => ref.read(authViewModelProvider.notifier).signOut(),
                child: Text('Log out', style: AppTextStyles.linkText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    this.onRetry,
    this.isRetrying = false,
  });

  final String title;
  final String body;

  /// Shows a retry button when the failure is transient.
  final VoidCallback? onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.displayHeading),
              const SizedBox(height: 8),
              Text(body, style: AppTextStyles.body),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                SerafimButton(
                  label: isRetrying ? 'Retrying…' : 'Retry',
                  onPressed: isRetrying ? null : onRetry,
                  fullWidth: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
