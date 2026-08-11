import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/login_form_state.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
import 'package:serafim/src/presentation/viewmodel/login_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/signup_view_model.dart';

/// The session. Long-lived — never auto-disposed, or the user would be signed
/// out whenever the last screen watching it left the tree.
final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(
  AuthViewModel.new,
);

/// Convenience reads so widgets can watch one field instead of rebuilding on
/// every [AuthState] change.
final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authViewModelProvider.select((state) => state.status));
});

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authViewModelProvider.select((state) => state.user));
});

/// Just the signed-in account's id, or null when signed out.
///
/// Anything scoped to "this account" should watch *this* rather than the auth
/// status: status returns to `authenticated` when a different person signs in,
/// so a provider keyed on status alone would carry the previous account's
/// state over. Keyed on the id, it rebuilds whenever the account changes.
final currentAccountIdProvider = Provider<String?>((ref) {
  return ref.watch(authViewModelProvider.select((state) => state.user?.id));
});

/// Sign-up form state.
///
/// Auto-disposed: leaving the screen should throw away what was typed, and a
/// half-filled form must not reappear on a later visit.
final signupViewModelProvider =
    NotifierProvider<SignupViewModel, SignupFormState>(
      SignupViewModel.new,
      isAutoDispose: true,
    );

final loginViewModelProvider = NotifierProvider<LoginViewModel, LoginFormState>(
  LoginViewModel.new,
);
