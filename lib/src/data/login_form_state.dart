/// State of the login form UI.
class LoginFormState {
  const LoginFormState({
    this.email = '',
    this.password = '',
    this.emailError,
    this.passwordError,
    this.formError,
    this.isSubmitting = false,
  });

  final String email;
  final String password;
  final String? emailError;
  final String? passwordError;
  final String? formError;
  final bool isSubmitting;

  bool get canSubmit =>
      email.isNotEmpty &&
      password.isNotEmpty &&
      emailError == null &&
      passwordError == null &&
      !isSubmitting;

  LoginFormState copyWith({
    String? email,
    String? password,
    Object? emailError = _unset,
    Object? passwordError = _unset,
    Object? formError = _unset,
    bool? isSubmitting,
  }) {
    return LoginFormState(
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
    );
  }
}

const Object _unset = Object();
