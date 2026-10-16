import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/config/feature_flags.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/core/platform/google_support.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/presentation/view/landing_page.dart';
import 'package:serafim/src/presentation/view/login_page.dart';
import 'package:serafim/src/presentation/view/signup_page.dart';
import 'package:serafim/src/utils/app_bottom_nav.dart';
import 'package:serafim/src/utils/avatar_picker.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';

/// Pretends to be [p] for the rest of this test, and undoes it before the
/// framework checks that tests left nothing changed.
void usePlatform(TargetPlatform p) {
  debugDefaultTargetPlatformOverride = p;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

/// A widget test that pretends to be [platform]. The override is undone inside
/// the test body — the framework checks for leftovers before teardown runs.
void testOn(
  String name,
  TargetPlatform platform,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget app(Widget child) => ProviderScope(child: MaterialApp(home: child));

void main() {
  group('sign-in options follow the platform', () {
    test('Google is offered where the plugin exists, and nowhere else', () {
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        usePlatform(p);
        expect(googleSignInSupported, isTrue, reason: '$p');
      }
      for (final p in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        usePlatform(p);
        expect(googleSignInSupported, isFalse, reason: '$p');
      }
    });

    test('email sign-in turns itself on exactly when Google cannot work', () {
      usePlatform(TargetPlatform.android);
      expect(FeatureFlags.emailSignInAvailable, FeatureFlags.emailSignIn);
      usePlatform(TargetPlatform.linux);
      expect(FeatureFlags.emailSignInAvailable, isTrue);
    });

    testOn(
      'on a phone: Google only, no email buttons',
      TargetPlatform.android,
      (tester) async {
        await tester.pumpWidget(
          app(LandingPage(onSignUpTap: () {}, onLoginTap: () {})),
        );
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.text('Create Account'), findsNothing);
      },
    );

    testOn(
      'on Linux: no dead Google button, email buttons instead',
      TargetPlatform.linux,
      (tester) async {
        var signUp = 0, login = 0;
        await tester.pumpWidget(
          app(
            LandingPage(onSignUpTap: () => signUp++, onLoginTap: () => login++),
          ),
        );
        expect(find.text('Continue with Google'), findsNothing);
        expect(find.text('Create Account'), findsOneWidget);
        expect(find.textContaining('log In'), findsOneWidget);

        await tester.tap(find.text('Create Account'));
        await tester.tap(find.textContaining('log In'));
        expect([signUp, login], [1, 1]);
      },
    );

    testOn(
      'the login and sign-up pages drop Google on Linux',
      TargetPlatform.linux,
      (tester) async {
        await tester.pumpWidget(
          app(LoginPage(onBack: () {}, onSignUpTap: () {})),
        );
        expect(find.text('Continue with Google'), findsNothing);

        await tester.pumpWidget(
          app(SignupScreen(onBack: () {}, onLoginTap: () {})),
        );
        expect(find.text('Continue with Google'), findsNothing);
      },
    );

    testOn(
      'the login page still offers Google on a phone',
      TargetPlatform.android,
      (tester) async {
        await tester.pumpWidget(
          app(LoginPage(onBack: () {}, onSignUpTap: () {})),
        );
        expect(find.text('Continue with Google'), findsOneWidget);
      },
    );

    test(
      'asking for Google on an unsupported platform is a clear message, not silence',
      () {
        usePlatform(TargetPlatform.linux);
        expect(
          GoogleAuthService(
            webClientId: 'abc.apps.googleusercontent.com',
          ).signIn(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains("isn't available on this device"),
            ),
          ),
        );
      },
    );
  });

  group('upload spinners', () {
    testWidgets(
      'the profile picture shows a spinner and ignores taps while busy',
      (tester) async {
        var taps = 0;
        Widget picker({required bool busy}) => MaterialApp(
          home: Scaffold(
            body: AvatarPicker(
              busy: busy,
              busyLabel: 'Uploading…',
              onEditTap: () => taps++,
              onUploadTap: () => taps++,
            ),
          ),
        );

        await tester.pumpWidget(picker(busy: false));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Upload photo'), findsOneWidget);
        await tester.tap(find.text('Upload photo'));
        await tester.tap(find.byIcon(Icons.camera_alt_outlined));
        expect(taps, 2);

        await tester.pumpWidget(picker(busy: true));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Uploading…'), findsOneWidget);
        expect(find.text('Upload photo'), findsNothing);
        await tester.tap(find.text('Uploading…'), warnIfMissed: false);
        await tester.tap(
          find.byIcon(Icons.camera_alt_outlined),
          warnIfMissed: false,
        );
        expect(taps, 2, reason: 'busy must block starting a second upload');
      },
    );

    testWidgets('the attach button spins while a photo is being sent', (
      tester,
    ) async {
      var attaches = 0;
      Widget bar({required bool busy}) => MaterialApp(
        home: Scaffold(
          body: ChatInputBar(onAttach: () => attaches++, attachBusy: busy),
        ),
      );

      await tester.pumpWidget(bar(busy: false));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byIcon(Icons.attach_file));
      expect(attaches, 1);

      await tester.pumpWidget(bar(busy: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsNothing);
      await tester.tapAt(
        tester.getCenter(find.byType(CircularProgressIndicator)),
      );
      expect(attaches, 1, reason: 'no second photo while one is sending');
    });
  });

  group('bars sit clear of the screen edge', () {
    testWidgets('the chat input has extra room below it', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(),
            ),
          ),
        ),
      );
      final bar = tester.getRect(find.byType(ChatInputBar));
      final field = tester.getRect(find.byType(TextField));
      // 20px of padding under the field area (it was 10).
      expect(bar.bottom - field.bottom, greaterThanOrEqualTo(20));
    });

    testWidgets('the bottom nav buttons are lifted off the edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                AppBottomNavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Home',
                ),
                AppBottomNavItem(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: 'Me',
                ),
              ],
            ),
          ),
        ),
      );
      final nav = tester.getRect(find.byType(AppBottomNav));
      final label = tester.getRect(find.text('HOME'));
      expect(nav.bottom - label.bottom, greaterThanOrEqualTo(10));
      expect(nav.height, greaterThanOrEqualTo(68));
    });
  });
}
