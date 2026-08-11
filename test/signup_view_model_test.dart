import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/presentation/viewmodel/signup_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';

/// Validation lives in the view model, so it can be tested without a widget
/// tree or a network stub. Every case below fails validation locally, so
/// `submit()` returns before it ever reaches AuthViewModel — no dio client is
/// ever constructed and no override is needed.
void main() {
  late ProviderContainer container;
  SignupViewModel viewModel() =>
      container.read(signupViewModelProvider.notifier);
  SignupFormState formState() => container.read(signupViewModelProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  group('copyWith', () {
    test('omitting an error keeps it, passing null clears it', () {
      const state = SignupFormState(
        emailError: 'bad email',
        passwordError: 'too short',
      );

      expect(state.copyWith(email: 'a@b.co').emailError, 'bad email',
          reason: 'an omitted error must survive an unrelated change');
      expect(state.copyWith(emailError: null).emailError, isNull);
      expect(state.copyWith(emailError: null).passwordError, 'too short',
          reason: 'clearing one error must not clear the others');
    });

    test('an explicit error is not swallowed', () {
      // Regression: copyWith once had a `clearErrors` flag that took priority
      // over the values passed alongside it, so submit() set every validation
      // message and immediately nulled it. The form refused to submit and
      // showed no reason why.
      const state = SignupFormState();

      final next = state.copyWith(emailError: 'Enter your email.');

      expect(next.emailError, 'Enter your email.');
    });
  });

  group('submit validation', () {
    test('empty fields produce a message on each', () async {
      expect(await viewModel().submit(), isFalse);

      expect(formState().emailError, 'Enter your email.');
      expect(formState().passwordError, 'Choose a password.');
      expect(formState().hasAttemptedSubmit, isTrue);
    });

    test('a malformed email is reported', () async {
      viewModel().emailChanged('not-an-email');
      viewModel().passwordChanged('longenoughpassword');

      expect(await viewModel().submit(), isFalse);
      expect(formState().emailError, contains('does not look like an email'));
      expect(formState().passwordError, isNull);
    });

    test('a short password says how many characters are missing', () async {
      viewModel().emailChanged('you@sector76.com');
      viewModel().passwordChanged('abc123');

      expect(await viewModel().submit(), isFalse);
      expect(formState().passwordError, 'Use at least 8 characters (2 more to go).');
      expect(formState().emailError, isNull);
    });

    test('a password past the bcrypt limit is rejected', () async {
      viewModel().emailChanged('you@sector76.com');
      viewModel().passwordChanged('x' * 73);

      expect(await viewModel().submit(), isFalse);
      expect(formState().passwordError, 'Use 72 characters or fewer.');
    });

    test('surrounding whitespace in the email is tolerated', () async {
      viewModel().emailChanged('  you@sector76.com  ');
      viewModel().passwordChanged('short');

      expect(await viewModel().submit(), isFalse);
      expect(formState().emailError, isNull,
          reason: 'the email is valid once trimmed');
    });
  });

  group('live re-validation', () {
    test('stays quiet until the first submit', () {
      viewModel().emailChanged('nope');
      viewModel().passwordChanged('x');

      expect(formState().emailError, isNull);
      expect(formState().passwordError, isNull);
    });

    test('updates as the user types once they have tried', () async {
      await viewModel().submit();
      expect(formState().emailError, isNotNull);

      viewModel().emailChanged('you@sector76.com');
      expect(formState().emailError, isNull,
          reason: 'fixing the field should clear its message immediately');

      viewModel().emailChanged('broken');
      expect(formState().emailError, isNotNull,
          reason: 'breaking it again should say so without another submit');
    });

    test('editing a field does not clear the other field error', () async {
      await viewModel().submit();
      expect(formState().passwordError, isNotNull);

      viewModel().emailChanged('you@sector76.com');

      expect(formState().passwordError, isNotNull);
    });
  });

  test('form state starts empty and submittable', () {
    const state = SignupFormState();

    expect(state.email, isEmpty);
    expect(state.canSubmit, isTrue);
    expect(state.hasErrors, isFalse);
    expect(const SignupFormState(isSubmitting: true).canSubmit, isFalse);
  });
}
