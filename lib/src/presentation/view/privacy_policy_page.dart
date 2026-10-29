import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The Privacy Policy: how Serafim handles your personal data.
///
/// Reached from the sign-up consent ("By signing up you agree to Serafim's
/// Terms and Privacy Policy.") and from the Settings menu, under About.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  /// Shown under the page title; bump when the Policy actually change.
  static const String lastUpdated = 'October 25, 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'PRIVACY POLICY',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This Privacy Policy explains how the developer of Serafim ("the '
                'Developer", "we", "us", "our") collects, uses, stores, shares and '
                'protects your personal information when you use the Serafim '
                'Service. It should be read together with the Terms of Service, '
                'which govern your use of the app. We apply the data protection '
                'principles of Malawi\'s Data Protection Act and similar laws, and '
                'GDPR-style principles where they apply to users in the European '
                'Union or European Economic Area.',
                style: AppTextStyles.legalBody,
              ),
              const SizedBox(height: 26),

              _section(
                first: true,
                heading: 'Information we collect',
                paragraphs: [
                  'We collect the following personal information when you use '
                      'Serafim:',
                ],
                bullets: [
                  'Account information: your Serafim user ID, the email address you '
                      'signed up with, and - when you sign in with Google - your '
                      'Google account identifiers and the profile details Google '
                      'shares with us.',
                  'Profile information: your display name, username, bio, profile '
                      'photo, interests, friend and follower relationships, and the '
                      'privacy settings you choose, such as who may send you friend '
                      'requests or add you to groups.',
                  'Content you create: posts, comments, chat messages and media '
                      'attachments, reactions (sparks), and group information.',
                  'Device and technical information: device identifiers, operating '
                      'system and version, app version, IP address, push notification '
                      'tokens, and diagnostics.',
                ],
                afterBullets: Text(
                  'We do not knowingly collect precise GPS location or payment '
                  'information.',
                ),
              ),
              _section(
                heading: 'How we use your information',
                paragraphs: [
                  'We use your information to create and authenticate your account, '
                      'store and deliver content and messages, operate feeds, circles, '
                      'groups and chats, send notifications, enforce our rules and '
                      'keep the Service safe, and understand how the Service is used '
                      'so we can improve it.',
                ],
              ),
              _section(
                heading: 'Legal bases for our use',
                paragraphs: [
                  'We process personal data on the basis of consent (for example when '
                      'you sign up and accept the Terms), the performance of a contract '
                      'with you, our legitimate interests in operating and securing the '
                      'Service, and legal obligations. We apply data protection '
                      'principles - lawfulness and legitimacy of processing, purpose '
                      'limitation, data minimisation, accuracy, storage limitation, '
                      'integrity and confidentiality.',
                ],
              ),
              _section(
                heading: 'How we share information',
                paragraphs: [
                  'We do not sell your personal information. We share it only with '
                      'the service providers that help us run the Service - including '
                      'authentication, hosting, storage, cloud and push notification '
                      'providers - and with other users when you share content with '
                      'them, such as a post visible to your circles or a message '
                      'delivered to a friend. We may also disclose information where '
                      'required by law or to protect the rights and safety of people.',
                ],
              ),
              _section(
                heading: 'Retention and deletion',
                paragraphs: [
                  'We keep your account information and content for as long as your '
                      'account is active and needed to provide the Service. You can '
                      'delete individual messages or posts from within the app; chat '
                      'messages also have a per-device retention setting (by default '
                      'they are kept). Chat backups you save to Google Drive are '
                      'handled by Google. When you delete your account, we delete or '
                      'deactivate the associated personal data, subject to any '
                      'retention obligations under applicable law.',
                ],
              ),
              _section(
                heading: 'Security',
                paragraphs: [
                  'We use reasonable technical and organisational measures - '
                      'including encryption in transit and access controls - to '
                      'protect your information. No method of transmission or '
                      'storage is completely secure, and we cannot guarantee absolute '
                      'security.',
                ],
              ),
              _section(
                heading: 'Your rights',
                paragraphs: [
                  'Depending on where you live, you may have rights to access, '
                      'correct, delete, export or object to the processing of your '
                      'personal data, and to withdraw consent. These rights may be '
                      'provided directly by the data protection law that applies to '
                      'you - including the GDPR for users in the European Union or '
                      'European Economic Area, and Malawi\'s Data Protection Act. To '
                      'exercise them, contact the Developer through the Serafim GitHub '
                      'repository. You also have the right to lodge a complaint with '
                      'the relevant data protection authority.',
                ],
              ),
              _section(
                heading: 'Children\'s privacy',
                paragraphs: [
                  'Serafim is not directed at children below the minimum age '
                      'described in the Terms of Service. We do not knowingly collect '
                      'personal information from children. If we learn that we have '
                      'collected it, we will delete it.',
                ],
              ),
              _section(
                heading: 'International transfers',
                paragraphs: [
                  'Your information may be processed in Malawi and by service '
                      'providers that may be located outside Malawi, including in '
                      'other countries. Where data crosses borders, we rely on '
                      'appropriate safeguards.',
                ],
              ),
              _section(
                heading: 'Changes and contact',
                paragraphs: [
                  'We may update this Privacy Policy. The current version is always '
                      'available in the app and is marked with a date. Your continued '
                      'use of the Service after a change takes effect means you accept '
                      'the updated Policy. Questions about this Policy can be sent to '
                      'the Developer through the Serafim GitHub repository.',
                ],
              ),

              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(
                  child: Text(
                    'Last updated: $lastUpdated',
                    style: AppTextStyles.legalMeta,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One titled block of the Privacy Policy: a heading, plain paragraphs, an
  /// optional bullet list, and an optional trailing paragraph.
  Widget _section({
    bool first = false,
    required String heading,
    required List<String> paragraphs,
    List<String>? bullets,
    Widget? afterBullets,
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
            if (afterBullets != null) ...[
              afterBullets,
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}
