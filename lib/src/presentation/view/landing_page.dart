import 'package:flutter/material.dart';
import 'package:serafim/src/core/config/feature_flags.dart';
import 'package:serafim/src/core/platform/google_support.dart';
import 'package:serafim/src/utils/google_sign_in_button.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
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
              const SerafimMark(size: 84),
              const SizedBox(height: 22),
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

              // Google comes first. It only accepts accounts Google has
              // already verified, which is why it is the one sign-in on offer
              // while email addresses are not confirmed.
              if (googleSignInSupported) ...[
                const GoogleSignInButton(),
                const SizedBox(height: 16),
              ],

              if (FeatureFlags.emailSignInAvailable) ...[
                // The divider only makes sense between two options.
                if (googleSignInSupported) ...[
                  const SerafimDivider(),
                  const SizedBox(height: 16),
                ],

                SerafimButton(label: 'Create Account', onPressed: onSignUpTap),
                const SizedBox(height: 12),

                SerafimButton(
                  label: 'Already have an account? log In',
                  onPressed: onLoginTap,
                  isPrimary: false,
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
