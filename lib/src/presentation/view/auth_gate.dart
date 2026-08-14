import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';
import 'package:serafim/src/presentation/view/landing_page.dart';
import 'package:serafim/src/presentation/view/login_page.dart';
import 'package:serafim/src/presentation/view/main_screen.dart';
import 'package:serafim/src/presentation/view/onboarding_flow.dart';
import 'package:serafim/src/presentation/view/signup_page.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/onboarding_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

enum _UnauthedView { landing, signup, login }

/// Central authentication gatekeeper that routes users based on [AuthStatus].
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  _UnauthedView _currentView = _UnauthedView.landing;

  @override
  Widget build(BuildContext context) {
    final configError = ref.watch(appConfigProvider).configurationError;
    if (configError != null) {
      return _Message(title: 'Not configured', body: configError);
    }

    final status = ref.watch(authStatusProvider);

    return switch (status) {
      AuthStatus.unknown => const _Splash(),

      AuthStatus.unauthenticated => switch (_currentView) {
        _UnauthedView.landing => LandingPage(
          onSignUpTap: () =>
              setState(() => _currentView = _UnauthedView.signup),
          onLoginTap: () => setState(() => _currentView = _UnauthedView.login),
        ),
        _UnauthedView.signup => SignupScreen(
          onBack: () => setState(() => _currentView = _UnauthedView.landing),
          onLoginTap: () => setState(() => _currentView = _UnauthedView.login),
        ),
        _UnauthedView.login => LoginPage(
          onBack: () => setState(() => _currentView = _UnauthedView.landing),
          onSignUpTap: () =>
              setState(() => _currentView = _UnauthedView.signup),
        ),
      },

      AuthStatus.awaitingEmailConfirmation => const _Message(
        title: 'Check your email',
        body:
            'We sent you a confirmation link. Open it, then come back and log in.',
      ),

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
        if (profile != null || onboarding.completed) {
          return const MainScreen();
        }
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

class Home extends ConsumerWidget {
  const Home();

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
