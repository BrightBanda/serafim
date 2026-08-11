import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/google_button.dart';
import 'package:serafim/src/utils/password_field.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/serafim_divider.dart';
import 'package:serafim/src/utils/text_field.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({
    super.key,
    this.emailController,
    this.passwordController,
    this.onBack,
    this.onLogIn,
    this.onGoogleContinue,
    this.onForgotPassword,
    this.onSignUpTap,
  });

  final TextEditingController? emailController;
  final TextEditingController? passwordController;
  final VoidCallback? onBack;
  final VoidCallback? onLogIn;
  final VoidCallback? onGoogleContinue;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onSignUpTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(onBack: onBack),
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

              // Form fields
              SerafimTextField(
                label: 'Email',
                controller: emailController,
                hintText: 'you@sector76.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              SerafimPasswordField(
                controller: passwordController,
                hintText: 'Enter your password',
              ),
              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: onForgotPassword,
                  child: Text(
                    'Forgot password?',
                    style: AppTextStyles.linkText.copyWith(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              SerafimButton(label: 'Log in', onPressed: onLogIn),
              const SizedBox(height: 18),

              const SerafimDivider(),
              const SizedBox(height: 18),

              GoogleButton(onPressed: onGoogleContinue),
              const SizedBox(height: 22),

              Center(
                child: GestureDetector(
                  onTap: onSignUpTap,
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
