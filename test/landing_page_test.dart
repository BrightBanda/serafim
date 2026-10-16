import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/config/feature_flags.dart';
import 'package:serafim/src/presentation/view/landing_page.dart';

void main() {
  testWidgets('offers Google first and hides email sign-in while it is off', (
    tester,
  ) async {
    var signUpTaps = 0, loginTaps = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LandingPage(
            onSignUpTap: () => signUpTaps++,
            onLoginTap: () => loginTaps++,
          ),
        ),
      ),
    );

    expect(FeatureFlags.emailSignIn, isFalse);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Create Account'), findsNothing);
    expect(find.textContaining('log In'), findsNothing);
    expect(find.text('Sign up'), findsNothing);
    expect(signUpTaps + loginTaps, 0);
  });
}
