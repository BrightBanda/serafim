import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/config/feature_flags.dart';
import 'package:serafim/src/presentation/view/landing_page.dart';

void main() {
  testWidgets('offers Google first, with email sign-in below it', (
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

    expect(FeatureFlags.emailSignIn, isTrue);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Create Account')).dy,
      greaterThan(tester.getTopLeft(find.text('Continue with Google')).dy),
    );
    await tester.tap(find.text('Create Account'));
    await tester.tap(find.textContaining('log In'));
    expect([signUpTaps, loginTaps], [1, 1]);
  });
}
