import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/google_button.dart';
import 'package:serafim/src/utils/password_field.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/serafim_divider.dart';
import 'package:serafim/src/utils/text_field.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, required this.onBack, required this.onSignUpTap});

  final VoidCallback onBack;
  final VoidCallback onSignUpTap;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginPressed() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    final success = await ref.read(loginViewModelProvider.notifier).submit();

    // On success, AuthGate automatically navigates away.
    // If it fails, state.formError will display on the screen automatically.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginViewModelProvider);
    final notifier = ref.read(loginViewModelProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(onBack: widget.onBack),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Heading block
              Text('WELCOME BACK', style: AppTextStyles.eyebrow),
              const SizedBox(height: 6),
              Text('Log in', style: AppTextStyles.displayHeading),
              const SizedBox(height: 6),
              Text(
                'Pick up where you left off — your feed, your people, your chats.',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 22),

              // Server/Form General Error Banner
              if (state.formError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade400),
                  ),
                  child: Text(
                    state.formError!,
                    style: AppTextStyles.body.copyWith(
                      color: Colors.red.shade300,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Form fields
              SerafimTextField(
                label: 'Email',
                controller: _emailController,
                hintText: 'you@sector76.com',
                keyboardType: TextInputType.emailAddress,
                errorText: state.emailError,
                onChanged: notifier.emailChanged,
              ),
              const SizedBox(height: 14),

              SerafimPasswordField(
                controller: _passwordController,
                hintText: 'Enter your password',
                errorText: state.passwordError,
                onChanged: notifier.passwordChanged,
              ),
              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    // Implement forgot password logic here when ready
                  },
                  child: Text(
                    'Forgot password?',
                    style: AppTextStyles.linkText.copyWith(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Log in action button
              SerafimButton(
                label: state.isSubmitting ? 'Logging in…' : 'Log in',
                onPressed: (state.canSubmit && !state.isSubmitting)
                    ? _onLoginPressed
                    : null,
              ),
              const SizedBox(height: 18),

              const SerafimDivider(),
              const SizedBox(height: 18),

              GoogleButton(onPressed: null),
              const SizedBox(height: 22),

              Center(
                child: GestureDetector(
                  onTap: widget.onSignUpTap,
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.smallDim,
                      children: [
                        const TextSpan(text: "Don't have an account? "),
                        TextSpan(
                          text: 'Sign up',
                          style: AppTextStyles.linkText,
                        ),
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
