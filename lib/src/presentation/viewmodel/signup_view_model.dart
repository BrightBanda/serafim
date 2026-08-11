import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';

/// Sentinel for [SignupFormState.copyWith].
///
/// The error fields are nullable and clearing one is a real operation, so
/// `null` cannot double as "leave this alone". Omitting an argument keeps the
/// current value; passing `null` explicitly clears it.
const Object _unset = Object();

/// Form state for the sign-up screen.
///
/// Kept separate from [AuthState] on purpose: this is throwaway per-screen
/// state (what is typed, what is invalid), while [AuthState] is the long-lived
/// session. Mixing them would mean a stale validation error survives sign-out.
class SignupFormState {
  const SignupFormState({
    this.email = '',
    this.password = '',
    this.emailError,
    this.passwordError,
    this.formError,
    this.isSubmitting = false,
    this.hasAttemptedSubmit = false,
  });

  final String email;
  final String password;

  /// Per-field messages, shown under the offending input.
  final String? emailError;
  final String? passwordError;

  /// Whole-form failure, e.g. "User already registered" from Supabase, which
  /// belongs to neither field on its own.
  final String? formError;

  final bool isSubmitting;

  /// True once Sign up has been pressed at least once.
  ///
  /// Before that, a field is not marked invalid while it is still being filled
  /// in — nobody wants "that does not look like an email" after one keystroke.
  /// Afterwards validation runs on every change, so fixing a field clears its
  /// message immediately instead of waiting for another submit.
  final bool hasAttemptedSubmit;

  bool get canSubmit => !isSubmitting;

  bool get hasErrors =>
      emailError != null || passwordError != null || formError != null;

  SignupFormState copyWith({
    String? email,
    String? password,
    Object? emailError = _unset,
    Object? passwordError = _unset,
    Object? formError = _unset,
    bool? isSubmitting,
    bool? hasAttemptedSubmit,
  }) {
    return SignupFormState(
      email: email ?? this.email,
      password: password ?? this.password,
      emailError: identical(emailError, _unset)
          ? this.emailError
          : emailError as String?,
      passwordError: identical(passwordError, _unset)
          ? this.passwordError
          : passwordError as String?,
      formError: identical(formError, _unset)
          ? this.formError
          : formError as String?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      hasAttemptedSubmit: hasAttemptedSubmit ?? this.hasAttemptedSubmit,
    );
  }
}

/// Validation and submission for the sign-up screen.
///
/// The widget holds no logic: it forwards keystrokes here and renders whatever
/// comes back. Validation lives here too so it can be unit-tested without
/// pumping a widget.
class SignupViewModel extends Notifier<SignupFormState> {
  // Deliberately loose. Real address validation is the confirmation email's
  // job; this only catches obvious typos before spending a round trip.
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Matches Supabase's default minimum. Change both together.
  static const minPasswordLength = 8;

  /// Supabase hashes with bcrypt, which ignores anything past 72 bytes.
  /// Rejecting here beats letting someone set a long passphrase whose tail
  /// silently does not count.
  static const maxPasswordLength = 72;

  @override
  SignupFormState build() => const SignupFormState();

  void emailChanged(String value) {
    state = state.copyWith(
      email: value,
      emailError: state.hasAttemptedSubmit ? _validateEmail(value.trim()) : null,
      // Any edit invalidates a server complaint about the previous input.
      formError: null,
    );
  }

  void passwordChanged(String value) {
    state = state.copyWith(
      password: value,
      passwordError: state.hasAttemptedSubmit ? _validatePassword(value) : null,
      formError: null,
    );
  }

  /// Validates, then delegates the actual auth work to [AuthViewModel].
  ///
  /// Returns true when the account was created; the screen uses that to
  /// navigate or show the "check your email" state.
  Future<bool> submit() async {
    final email = state.email.trim();
    final password = state.password;

    final emailError = _validateEmail(email);
    final passwordError = _validatePassword(password);

    state = state.copyWith(
      hasAttemptedSubmit: true,
      emailError: emailError,
      passwordError: passwordError,
      formError: null,
    );

    if (emailError != null || passwordError != null) return false;

    state = state.copyWith(isSubmitting: true);

    try {
      await ref
          .read(authViewModelProvider.notifier)
          .signUp(email: email, password: password);
      if (ref.mounted) state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (error) {
      if (ref.mounted) {
        // Supabase rejects a duplicate address. Attach that to the field that
        // caused it instead of the banner — showing both says the same thing
        // twice in two different wordings.
        final isDuplicate = _isDuplicateAccount(error);
        state = state.copyWith(
          isSubmitting: false,
          emailError: isDuplicate ? 'That email is already registered.' : null,
          formError: isDuplicate ? null : error.message,
        );
      }
      return false;
    }
  }

  static bool _isDuplicateAccount(ApiException error) {
    final message = error.message.toLowerCase();
    return message.contains('already registered') ||
        message.contains('already exists') ||
        error.code == 'user_already_exists';
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Enter your email.';
    if (!_emailPattern.hasMatch(email)) {
      return 'That does not look like an email — check for a missing @ or domain.';
    }
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) return 'Choose a password.';
    if (password.length < minPasswordLength) {
      final missing = minPasswordLength - password.length;
      return 'Use at least $minPasswordLength characters ($missing more to go).';
    }
    if (password.length > maxPasswordLength) {
      return 'Use $maxPasswordLength characters or fewer.';
    }
    return null;
  }
}
