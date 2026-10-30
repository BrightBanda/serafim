import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/services/profile_service.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/presentation/viewmodel/onboarding_view_model.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/onboarding_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';

/// Stands in for the signed-in account so a test can switch users without
/// driving a real sign-in. A plain [Notifier] rather than StateProvider,
/// which moved to `flutter_riverpod/legacy.dart` in Riverpod 3.
class _Account extends Notifier<String?> {
  @override
  String? build() => 'account-a';

  void signInAs(String? id) => state = id;
}

final _account = NotifierProvider<_Account, String?>(_Account.new);

class _TakenUsernameProfiles extends ProfileService {
  _TakenUsernameProfiles() : super(Dio());

  final requests = <ProfileCreateRequest>[];

  @override
  Future<Profile?> getMine() async => null;

  @override
  Future<Profile> create(ProfileCreateRequest request) async {
    requests.add(request);
    throw const ApiException(
      'That username is already taken. Try another one.',
    );
  }
}

void main() {
  late ProviderContainer container;

  OnboardingViewModel viewModel() =>
      container.read(onboardingViewModelProvider.notifier);
  OnboardingState state() => container.read(onboardingViewModelProvider);
  void signInAs(String? id) => container.read(_account.notifier).signInAs(id);

  setUp(() {
    container = ProviderContainer(
      overrides: [
        currentAccountIdProvider.overrideWith((ref) => ref.watch(_account)),
      ],
    );
  });
  tearDown(() => container.dispose());

  group('step navigation', () {
    test('starts on the photo/name step', () {
      expect(state().step, OnboardingStep.photoName);
      expect(state().completed, isFalse);
    });

    test('continue advances and keeps the trimmed name', () {
      viewModel().continueToInterests(
        '  Bright Banda  ',
        username: ' Bright_Banda ',
      );

      expect(state().step, OnboardingStep.interests);
      expect(state().displayName, 'Bright Banda');
      expect(state().username, 'bright_banda');
    });

    test('back preserves what was typed', () {
      viewModel().continueToInterests('Bright');
      viewModel().backToPhotoName();

      expect(state().step, OnboardingStep.photoName);
      expect(
        state().displayName,
        'Bright',
        reason: 'stepping back must not discard the name',
      );
    });
  });

  test('a taken username is shown and never silently replaced', () async {
    final profiles = _TakenUsernameProfiles();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        currentAccountIdProvider.overrideWith((ref) => ref.watch(_account)),
        currentUserProvider.overrideWithValue(
          AppUser(
            id: 'account-a',
            email: 'person@example.com',
            isActive: true,
            createdAt: DateTime.utc(2026),
          ),
        ),
        profileServiceProvider.overrideWithValue(profiles),
        profileViewModelProvider.overrideWith(_TestProfileViewModel.new),
      ],
    );

    viewModel().continueToInterests('Person', username: 'taken_name');
    await viewModel().finish({});

    expect(profiles.requests, hasLength(1));
    expect(profiles.requests.single.username, 'taken_name');
    expect(state().step, OnboardingStep.photoName);
    expect(state().usernameError, contains('username is already taken'));
    expect(state().errorMessage, isNull);
    expect(state().isSubmitting, isFalse);
  });

  group('resets per account', () {
    // Regression: onboardingViewModelProvider is not auto-disposed, so
    // `completed` from the first sign-up used to survive a sign-out. The next
    // account was sent straight to home and never saw profile setup.
    test('signing in as someone else clears progress', () {
      viewModel().continueToInterests('First User');
      expect(state().step, OnboardingStep.interests);

      signInAs('account-b');

      expect(state().step, OnboardingStep.photoName);
      expect(state().displayName, isEmpty);
      expect(state().completed, isFalse);
    });

    test('signing out clears progress', () {
      viewModel().continueToInterests('First User');

      signInAs(null);

      expect(state().step, OnboardingStep.photoName);
      expect(state().displayName, isEmpty);
    });

    test('staying on the same account does not reset mid-flow', () {
      viewModel().continueToInterests('Bright');

      signInAs('account-a'); // same id, no real change

      expect(state().step, OnboardingStep.interests);
      expect(state().displayName, 'Bright');
    });
  });
}

class _TestProfileViewModel extends ProfileViewModel {
  @override
  Future<Profile?> build() async => null;
}
