import 'package:flutter/material.dart';
import 'package:serafim/src/utils/google_button.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/serafim_divider.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({
    super.key,
    required this.onSignUpTap,
    required this.onLoginTap,
  });

  final VoidCallback onSignUpTap;
  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              // Branding & Tagline
              Text('SERAFIM', style: AppTextStyles.eyebrow),
              const SizedBox(height: 8),
              Text(
                'Connect across\nevery sector.',
                style: AppTextStyles.displayHeading,
              ),
              const SizedBox(height: 12),
              Text(
                'Join the feed, find your people, and start real-time conversations.',
                style: AppTextStyles.body,
              ),

              const Spacer(),

              // Action Buttons
              SerafimButton(label: 'Create Account', onPressed: onSignUpTap),
              const SizedBox(height: 12),

              SerafimButton(
                label: 'Log In',
                onPressed: onLoginTap,
                isPrimary: false,
              ),
              const SizedBox(height: 20),

              const SerafimDivider(),
              const SizedBox(height: 20),

              // Social Auth Option
              GoogleButton(onPressed: null),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
