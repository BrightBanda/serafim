import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/login_form_state.dart';
import 'package:serafim/src/providers/auth_providers.dart';

class LoginViewModel extends Notifier<LoginFormState> {
  @override
  LoginFormState build() => const LoginFormState();

  void emailChanged(String email) {
    final trimmed = email.trim();
    String? error;
    if (trimmed.isEmpty) {
      error = 'Email is required';
    } else if (!trimmed.contains('@')) {
      error = 'Enter a valid email address';
    }

    state = state.copyWith(email: trimmed, emailError: error, formError: null);
  }

  void passwordChanged(String password) {
    String? error;
    if (password.isEmpty) {
      error = 'Password is required';
    }

    state = state.copyWith(
      password: password,
      passwordError: error,
      formError: null,
    );
  }

  /// Attempts sign in via [AuthViewModel].
  ///
  /// Returns `true` on success, `false` on failure (and stores the error in state).
  Future<bool> submit() async {
    if (!state.canSubmit) return false;

    state = state.copyWith(isSubmitting: true, formError: null);

    try {
      await ref
          .read(authViewModelProvider.notifier)
          .signIn(email: state.email, password: state.password);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isSubmitting: false, formError: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        formError: 'An unexpected error occurred. Please try again.',
      );
      return false;
    }
  }
}
