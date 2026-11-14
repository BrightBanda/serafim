import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/auth_session.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/presentation/view/email_code_page.dart';
import 'package:serafim/src/presentation/view/signup_page.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Answers like Supabase would, and remembers what it was asked.
class CodeAuth extends FakeAuthService {
  SignUpResult signUpAnswer = const SignUpResult.awaitingConfirmation();
  Object? signInError;
  String rightCode = '123456';
  final calls = <String>[];

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    calls.add('signUp $email');
    return signUpAnswer;
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('signIn $email');
    if (signInError != null) throw signInError!;
    return fakeSession();
  }

  @override
  Future<AuthSession> verifySignupCode({
    required String email,
    required String code,
  }) async {
    calls.add('verify $email $code');
    if (code != rightCode) {
      throw const ApiException('Token has expired or is invalid');
    }
    return fakeSession();
  }

  @override
  Future<void> resendSignupCode(String email) async =>
      calls.add('resend $email');
}

Future<(ProviderContainer, CodeAuth)> build() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = CodeAuth();
  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sessionStoreProvider.overrideWithValue(FakeSessionStore(null)),
      userServiceProvider.overrideWithValue(
        FakeUserService(() async => fakeUser()),
      ),
      authServiceProvider.overrideWithValue(auth),
    ],
  );
  addTearDown(container.dispose);
  container.listen(authViewModelProvider, (_, _) {}, fireImmediately: true);
  await pumpEventQueue(times: 30);
  return (container, auth);
}

void main() {
  group('the service', () {
    late List<RequestOptions> sent;
    late AuthService service;
    setUp(() {
      sent = [];
      final dio = Dio(BaseOptions(baseUrl: 'https://x.test/auth/v1'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'access_token': 'a',
                  'refresh_token': 'r',
                  'expires_in': 3600,
                  'user': {'id': 'u1'},
                },
              ),
            );
          },
        ),
      );
      service = AuthService(dio);
    });

    test('verifying posts the code as a signup token', () async {
      final session = await service.verifySignupCode(
        email: 'a@b.co',
        code: '654321',
      );
      expect(session.accessToken, 'a');
      expect(sent.single.path, '/verify');
      expect(sent.single.data, {
        'type': 'signup',
        'email': 'a@b.co',
        'token': '654321',
      });
    });

    test('asking again posts a signup resend', () async {
      await service.resendSignupCode('a@b.co');
      expect(sent.single.path, '/resend');
      expect(sent.single.data, {'type': 'signup', 'email': 'a@b.co'});
    });
  });

  group('the view model', () {
    test('signing up asks for the code, and remembers where it went', () async {
      final (c, _) = await build();
      await c
          .read(authViewModelProvider.notifier)
          .signUp(email: 'a@b.co', password: 'pw');
      final s = c.read(authViewModelProvider);
      expect(s.status, AuthStatus.awaitingEmailConfirmation);
      expect(s.pendingEmail, 'a@b.co');
    });

    test('the right code signs in', () async {
      final (c, auth) = await build();
      final vm = c.read(authViewModelProvider.notifier);
      await vm.signUp(email: 'a@b.co', password: 'pw');
      await vm.verifyEmailCode('123456');
      expect(auth.calls, contains('verify a@b.co 123456'));
      expect(c.read(authViewModelProvider).status, AuthStatus.authenticated);
    });

    test('a wrong code is an error and keeps waiting', () async {
      final (c, _) = await build();
      final vm = c.read(authViewModelProvider.notifier);
      await vm.signUp(email: 'a@b.co', password: 'pw');
      await expectLater(
        vm.verifyEmailCode('000000'),
        throwsA(isA<ApiException>()),
      );
      final s = c.read(authViewModelProvider);
      expect(s.status, AuthStatus.awaitingEmailConfirmation);
      expect(s.isBusy, isFalse);
    });

    test('a new code can be asked for, and the address given up on', () async {
      final (c, auth) = await build();
      final vm = c.read(authViewModelProvider.notifier);
      await vm.signUp(email: 'a@b.co', password: 'pw');
      await vm.resendEmailCode();
      expect(auth.calls, contains('resend a@b.co'));
      vm.cancelEmailConfirmation();
      expect(c.read(authViewModelProvider).status, AuthStatus.unauthenticated);
      expect(c.read(authViewModelProvider).pendingEmail, isNull);
    });

    test(
      'logging in with an unconfirmed email sends a code and asks for it',
      () async {
        final (c, auth) = await build();
        auth.signInError = const ApiException(
          'x',
          statusCode: 400,
          code: 'email_not_confirmed',
        );
        await c
            .read(authViewModelProvider.notifier)
            .signIn(email: 'a@b.co', password: 'pw');
        expect(auth.calls, ['signIn a@b.co', 'resend a@b.co']);
        final s = c.read(authViewModelProvider);
        expect(s.status, AuthStatus.awaitingEmailConfirmation);
        expect(s.pendingEmail, 'a@b.co');
      },
    );

    test('other sign-in failures still show as errors', () async {
      final (c, auth) = await build();
      auth.signInError = const ApiException(
        'nope',
        code: 'invalid_credentials',
      );
      await expectLater(
        c
            .read(authViewModelProvider.notifier)
            .signIn(email: 'a@b.co', password: 'pw'),
        throwsA(isA<ApiException>()),
      );
      expect(auth.calls, ['signIn a@b.co']);
    });
  });

  group('the code screen', () {
    Future<(ProviderContainer, CodeAuth)> show(WidgetTester t) async {
      final (c, auth) =
          await t.runAsync(build) as (ProviderContainer, CodeAuth);
      await c
          .read(authViewModelProvider.notifier)
          .signUp(email: 'a@b.co', password: 'pw');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: EmailCodeScreen()),
        ),
      );
      return (c, auth);
    }

    testWidgets('says where the code went, and waits for six digits', (
      t,
    ) async {
      await show(t);
      expect(find.textContaining('a@b.co'), findsOneWidget);
      FilledButton? verify() => null;
      expect(verify(), isNull);
      await t.enterText(find.byType(TextField), '123');
      await t.pump();
      expect(find.text('Verify'), findsOneWidget);
      // Letters are not accepted.
      await t.enterText(find.byType(TextField), '12ab34');
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '1234',
      );
    });

    testWidgets('a right code signs in; a wrong one says so', (t) async {
      final (c, _) = await show(t);
      await t.enterText(find.byType(TextField), '000000');
      await t.pump();
      await t.tap(find.text('Verify'));
      await t.pump();
      await t.pump();
      expect(find.textContaining('wrong or has expired'), findsOneWidget);
      expect(
        c.read(authViewModelProvider).status,
        AuthStatus.awaitingEmailConfirmation,
      );

      await t.enterText(find.byType(TextField), '123456');
      await t.pump();
      await t.tap(find.text('Verify'));
      await t.pump();
      await t.runAsync(() => pumpEventQueue(times: 30));
      expect(c.read(authViewModelProvider).status, AuthStatus.authenticated);
    });

    testWidgets('a new code can be asked for only after a wait', (t) async {
      final (_, auth) = await show(t);
      expect(find.textContaining('Send a new code in'), findsOneWidget);
      await t.pump(EmailCodeScreen.resendWait + const Duration(seconds: 1));
      await t.tap(find.text('Send a new code'));
      await t.pump();
      await t.pump();
      expect(auth.calls, contains('resend a@b.co'));
      expect(find.text('A new code is on its way.'), findsOneWidget);
    });
  });

  testWidgets('sign-up asks for the password twice', (t) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignupScreen())),
    );
    expect(find.text('CONFIRM PASSWORD'), findsOneWidget);
    expect(find.byKey(const ValueKey('confirm-password')), findsOneWidget);
  });
}
