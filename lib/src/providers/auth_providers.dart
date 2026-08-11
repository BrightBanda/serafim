import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
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

/// Sign-up form state.
///
/// Auto-disposed: leaving the screen should throw away what was typed, and a
/// half-filled form must not reappear on a later visit.
final signupViewModelProvider =
    NotifierProvider<SignupViewModel, SignupFormState>(
      SignupViewModel.new,
      isAutoDispose: true,
    );
