import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/presentation/view/privacy_policy_page.dart';
import 'package:serafim/src/presentation/view/terms_of_service_page.dart';

void main() {
  group('terms of service page', () {
    testWidgets('renders the title and its sections', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TermsOfServicePage()));

      expect(find.text('TERMS OF SERVICE'), findsOneWidget);
      expect(
        find.textContaining('These Terms of Service ("Terms") govern your'),
        findsOneWidget,
      );
      expect(find.text('Acceptance of these Terms'), findsOneWidget);
      expect(find.text('Governing law and disputes'), findsOneWidget);
      expect(find.text('Read our Privacy Policy.'), findsOneWidget);
    });
  });

  group('privacy policy page', () {
    testWidgets('renders the title and its sections', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));

      expect(find.text('PRIVACY POLICY'), findsOneWidget);
      expect(find.text('Information we collect'), findsOneWidget);
      expect(find.text('How we use your information'), findsOneWidget);
      expect(find.text('Changes and contact'), findsOneWidget);
      expect(find.text('Last updated: October 25, 2026'), findsOneWidget);
    });
  });
}
