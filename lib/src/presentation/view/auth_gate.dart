import 'dart:async';

import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/utils/serafim_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// The mascot stays up for at least this long when the app opens, however
  /// fast it loads. Everything loads behind it meanwhile, so what comes next is
  /// ready the moment it goes.
  static const _splashAtLeast = Duration(milliseconds: 2500);
  static const _splashFade = Duration(milliseconds: 220);

  /// The first build of the main screen takes a good 150 ms whatever is done
  /// to it, which would stall a moving mascot. So the logo screen stays up
  /// until that is done: a still picture can't stutter, and the mascot then has
  /// a clear run. This long at most, for when loading is slow; it then waits on
  /// screen as usual.
  static const _logoAtMost = Duration(seconds: 2);

  /// The main screen's first data and start-up work come just after its first
  /// build, and were measured to be over by about this much later.
  static const _logoAfterLoaded = Duration(milliseconds: 650);

  Timer? _splashTimer;
  Timer? _logoTimer;
  bool _logoReleasing = false;
  bool _logoReleased = false;
  bool _splashHolding = true;
  bool _splashGone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.deferFirstFrame();
    _logoTimer = Timer(_logoAtMost, _releaseLogo);
  }

  /// Shows the first frame, and starts the mascot's time.
  void _releaseLogo() {
    if (_logoReleased) return;
    _logoReleased = true;
    _logoTimer?.cancel();
    WidgetsBinding.instance.allowFirstFrame();
    if (!mounted) return;
    _splashTimer = Timer(_splashAtLeast, () {
      if (mounted) setState(() => _splashHolding = false);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    // Never leave the app showing nothing.
    _releaseLogo();
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One mascot, on top: shown while opening, and whenever the app below has
    // nothing to show yet, so it never restarts or appears twice.
    final loading = _stillLoading();
    if (!loading && !_logoReleasing) {
      _logoReleasing = true;
      _logoTimer?.cancel();
      _logoTimer = Timer(_logoAfterLoaded, _releaseLogo);
    }
    final show = _splashHolding || loading;
    if (show) _splashGone = false;
    // The same shape throughout: the app below must not be rebuilt from scratch
    // when the mascot goes.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Page animations wait until they can be seen.
        TickerMode(enabled: !show, child: _content(context)),
        if (!_splashGone)
          IgnorePointer(
            ignoring: !show,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: _splashFade,
              onEnd: () {
                if (!show) setState(() => _splashGone = true);
              },
              child: const AbsorbPointer(child: _Splash()),
            ),
          ),
      ],
    );
  }

  /// Whether [_content] is waiting, with only an empty page to show.
  bool _stillLoading() {
    if (ref.watch(appConfigProvider).configurationError != null) return false;
    return switch (ref.watch(authStatusProvider)) {
      AuthStatus.unknown => true,
      AuthStatus.authenticated =>
        ref
            .watch(profileViewModelProvider)
            .maybeWhen(loading: () => true, orElse: () => false),
      _ => false,
    };
  }

  Widget _content(BuildContext context) {
    final configError = ref.watch(appConfigProvider).configurationError;
    if (configError != null) {
      return _Message(title: 'Not configured', body: configError);
    }

    final status = ref.watch(authStatusProvider);

    // "Your session ended" and the like: tell the person once, then forget it.
    ref.listen(authViewModelProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(notice)));
      ref.read(authViewModelProvider.notifier).clearNotice();
    });

    return switch (status) {
      // The mascot on top covers this.
      AuthStatus.unknown => ColoredBox(color: AppColors.paper),

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
        title: 'No connection',
        body: 'Check your internet and try again.',
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
      // The mascot on top covers this.
      loading: () => ColoredBox(color: AppColors.paper),
      error: (error, _) => _Message(
        title: 'Could not load your profile',
        body: humanError(error),
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
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: const Center(child: SerafimLoader(size: 170)),
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
