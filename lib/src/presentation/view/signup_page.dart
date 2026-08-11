import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/viewmodel/signup_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/utils/app_colors.dart';
import 'package:serafim/src/utils/app_text_styles.dart';
import 'package:serafim/src/utils/google_button.dart';
import 'package:serafim/src/utils/password_field.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/serafim_divider.dart';
import 'package:serafim/src/utils/text_field.dart';
import 'package:serafim/src/utils/top_bar.dart';

/// Sign-up screen.
///
/// Holds no logic beyond wiring: text goes to [SignupViewModel], and whatever
/// [SignupFormState] comes back gets rendered. Validation, the network call,
/// and the resulting session all live in the view models.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, this.onBack, this.onLoginTap});

  /// Navigation is still the caller's job — this screen does not know what
  /// sits above it in the stack.
  final VoidCallback? onBack;
  final VoidCallback? onLoginTap;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  // Controllers belong to the widget, not the view model: they are a Flutter
  // rendering concern with a dispose contract, and the view model must stay
  // testable without a widget tree.
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final created = await ref.read(signupViewModelProvider.notifier).submit();
    if (!created || !mounted) return;

    // On success AuthViewModel has already flipped to authenticated (or to
    // awaitingEmailConfirmation), so the gate above this screen swaps it out.
    // Nothing to do here but stop.
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(signupViewModelProvider);
    final viewModel = ref.read(signupViewModelProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: TopBar(onBack: widget.onBack),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Heading block
              Text('GET STARTED', style: AppTextStyles.eyebrow),
              const SizedBox(height: 6),
              Text('Create your account', style: AppTextStyles.displayHeading),
              const SizedBox(height: 6),
              Text(
                "Join the feed, find your people, and start chatting across every sector.",
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 22),

              // Form fields
              SerafimTextField(
                label: 'Email',
                controller: _emailController,
                hintText: 'you@sector76.com',
                keyboardType: TextInputType.emailAddress,
                onChanged: viewModel.emailChanged,
                errorText: form.emailError,
                enabled: !form.isSubmitting,
              ),
              const SizedBox(height: 14),
              SerafimPasswordField(
                controller: _passwordController,
                hintText: 'At least ${SignupViewModel.minPasswordLength} characters',
                helperText:
                    '${SignupViewModel.minPasswordLength} characters minimum',
                onChanged: viewModel.passwordChanged,
                errorText: form.passwordError,
                enabled: !form.isSubmitting,
              ),

              if (form.formError != null) ...[
                const SizedBox(height: 14),
                _FormError(message: form.formError!),
              ],

              const SizedBox(height: 18),

              SerafimButton(
                label: form.isSubmitting ? 'Creating account…' : 'Sign up',
                onPressed: form.canSubmit ? _submit : null,
              ),
              const SizedBox(height: 18),

              const SerafimDivider(),
              const SizedBox(height: 18),

              // Not wired yet: Google sign-in goes through Supabase OAuth,
              // which needs a redirect the app does not handle.
              GoogleButton(onPressed: null),
              const SizedBox(height: 18),

              Text(
                "By signing up you agree to Serafim's Terms and Privacy Policy.",
                textAlign: TextAlign.center,
                style: AppTextStyles.fieldLabel.copyWith(fontSize: 9.5),
              ),
              const SizedBox(height: 16),

              Center(
                child: GestureDetector(
                  onTap: widget.onLoginTap,
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.smallDim,
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(text: 'Log in', style: AppTextStyles.linkText),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whole-form failure banner — server-side rejections such as "User already
/// registered", which belong to neither field.
class _FormError extends StatelessWidget {
  const _FormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.rust, width: 1.5),
      ),
      child: Text(
        message,
        style: AppTextStyles.smallDim.copyWith(color: AppColors.rustPale),
      ),
    );
  }
}
