import 'package:flutter/material.dart';
import 'package:serafim/src/presentation/view/privacy_policy_page.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The Terms of Service: the rules for using Serafim.
///
/// Reached from the sign-up consent ("By signing up you agree to Serafim's
/// Terms and Privacy Policy.") and from the Settings menu, under About.
class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  /// Shown under the page title; bump when the Terms actually change.
  static const String lastUpdated = 'October 25, 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'TERMS OF SERVICE',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These Terms of Service ("Terms") govern your use of Serafim, the '
                'social app for sharing posts, sparks and real-time chat. They are '
                'a binding agreement between you and the developer of Serafim. The '
                'Privacy Policy explains how we handle your data; by creating an '
                'account or using the Service you accept both.',
                style: AppTextStyles.legalBody,
              ),
              const SizedBox(height: 8),
              Text(
                'Last updated: $lastUpdated',
                style: AppTextStyles.legalMeta,
              ),
              const SizedBox(height: 18),

              _section(
                first: true,
                heading: 'Acceptance of these Terms',
                paragraphs: [
                  'These Terms of Service ("Terms") are a legally binding agreement '
                      'between you and the developer of Serafim ("the Developer", '
                      '"we", "us", "our"). They apply whenever you create an account '
                      'for, sign in to, or otherwise use the Serafim mobile app and '
                      'the backend services it relies on.',
                  'By creating an account, signing in, or otherwise using the '
                      'Service you accept these Terms and the Privacy Policy. If you '
                      'do not accept them, you must not create an account or use the '
                      'Service.',
                  'If you use Serafim on behalf of a club, organisation or '
                      'community, you confirm that you have authority to accept '
                      'these Terms on its behalf.',
                ],
              ),
              _section(
                heading: 'Eligibility',
                paragraphs: [
                  'You must be at least 13 years old, or the minimum age of digital '
                      'consent in your country where that is higher, and must have '
                      'the legal capacity to agree to a contract. Where local law '
                      'requires parental or guardian consent for users below the '
                      'age of digital consent, such users may not use Serafim unless '
                      'a parent or legal guardian has given consent.',
                ],
              ),
              _section(
                heading: 'Your account and security',
                paragraphs: [
                  'You create an account with an email address and password, or by '
                      'signing in with a Google account. You agree to provide '
                      'accurate account information and to keep your credentials '
                      'confidential. You are responsible for keeping your account '
                      'and device secure and for all activity that happens through '
                      'your account.',
                  'You may not create more than one account for yourself, and you '
                      "may not use another person's account without their permission.",
                ],
              ),
              _section(
                heading: 'The service',
                paragraphs: [
                  'Serafim provides social features: posting in feeds and circles, '
                      'sparking posts, and real-time messaging and group chats. The '
                      'Service is provided on a best-effort basis and may be added '
                      'to, changed, suspended or discontinued at any time.',
                ],
              ),
              _section(
                heading: 'Acceptable use',
                paragraphs: [
                  'You may not use Serafim to break the law or these Terms, or to '
                      'harm the Service or other people.',
                ],
                bullets: [
                  'Harass, threaten, bully or defame others, or post content that '
                      'promotes violence, hatred or discrimination.',
                  'Share content that is unlawful, harmful, or sexual content '
                      'involving minors.',
                  'Impersonate another person or misrepresent your identity or '
                      'affiliation.',
                  'Send spam, malware or unsolicited content, or attempt to gain '
                      'unauthorised access to accounts or systems.',
                  'Collect or publish another person\'s personal information without '
                      'their consent.',
                ],
              ),
              _section(
                heading: 'Your content',
                paragraphs: [
                  'You keep ownership of the posts, comments, messages and media you '
                      'submit. By submitting content you grant the Developer and the '
                      'people it is shared with a non-exclusive, worldwide, royalty-free '
                      'licence to host, store, reproduce, display and distribute that '
                      'content for the purpose of operating and promoting the Service - '
                      'for example so your posts can appear in feeds and chats of your '
                      'friends and circles.',
                  'You confirm that you have the rights needed to post content, '
                      'including photo or video content that shows other people, and '
                      "that your content does not violate these Terms or anyone else's "
                      'rights.',
                ],
              ),
              _section(
                heading: 'Serafim intellectual property',
                paragraphs: [
                  'The Serafim name, logo, mark and all related design, branding and '
                      'software are owned by the Developer. You may not use them '
                      'without permission.',
                ],
              ),
              _section(
                heading: 'Third-party services',
                paragraphs: [
                  'Serafim relies on third-party providers - including Google for '
                      'sign-in and push notifications, and cloud, authentication and '
                      'storage providers - and your use of those services is also '
                      'subject to their terms and policies.',
                ],
              ),
              _section(
                heading: 'Disclaimers',
                paragraphs: [
                  'The Service is provided "as is" and "as available", without '
                      'warranties of any kind. We do not warrant that the Service will '
                      'be uninterrupted, secure or error-free, or that content on it is '
                      'lawful, accurate or appropriate.',
                ],
              ),
              _section(
                heading: 'Limitation of liability',
                paragraphs: [
                  'To the fullest extent permitted by applicable law, the Developer '
                      'is not liable for indirect, incidental, special or '
                      'consequential damages, or for any loss arising from user '
                      'content, conduct of other users or third-party services. The '
                      'Developer\'s total liability for any claim relating to the '
                      'Service is limited to the greater of the fees paid by you for '
                      'the Service in the twelve months before the claim and the '
                      'minimum amount allowed by applicable law.',
                ],
              ),
              _section(
                heading: 'Indemnification',
                paragraphs: [
                  'You agree to indemnify and hold the Developer harmless from any '
                      'claim arising out of your content or your breach of these Terms.',
                ],
              ),
              _section(
                heading: 'Termination',
                paragraphs: [
                  'You may stop using Serafim and delete your account at any time. '
                      'We may suspend or terminate your access to the Service if you '
                      'breach these Terms, with or without notice. The sections that '
                      'by their nature should survive a termination - including the '
                      'disclaimer of warranties and the limitation of liability - '
                      'survive.',
                ],
              ),
              _section(
                heading: 'Changes to these Terms',
                paragraphs: [
                  'We may update these Terms from time to time. The current version is '
                      'always available in the app and is marked with a date. Material '
                      'changes may require you to accept the new Terms. Your continued '
                      'use of the Service after a change takes effect means you accept '
                      'the updated Terms.',
                ],
              ),
              _section(
                heading: 'Governing law and disputes',
                paragraphs: [
                  'These Terms are governed by the laws of the Republic of Malawi, '
                      'without regard to conflict of law rules. Any dispute arising out '
                      'of or relating to these Terms or the Service will be subject to '
                      'the jurisdiction of the courts of Malawi, or to such other '
                      'dispute resolution mechanism as applicable law requires.',
                ],
              ),
              _section(
                heading: 'General',
                paragraphs: [
                  'These Terms are the entire agreement between you and the Developer '
                      'relating to the Service, and supersede any earlier agreements. '
                      'If any provision is found unenforceable, the remaining provisions '
                      'remain in effect. The Developer\'s failure to enforce a right is '
                      'not a waiver of it, and the Developer may assign these Terms '
                      'without your consent.',
                ],
              ),

              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    ),
                    child: Text(
                      'Read our Privacy Policy.',
                      style: AppTextStyles.linkText,
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

  /// One titled block of the Terms: a heading, plain paragraphs, and an
  /// optional bullet list.
  Widget _section({
    bool first = false,
    required String heading,
    required List<String> paragraphs,
    List<String>? bullets,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: AppTextStyles.legalHeading),
          const SizedBox(height: 8),
          for (final paragraph in paragraphs) ...[
            Text(paragraph, style: AppTextStyles.legalBody),
            const SizedBox(height: 8),
          ],
          if (bullets != null) ...[
            for (final bullet in bullets) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $bullet', style: AppTextStyles.legalBody),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
