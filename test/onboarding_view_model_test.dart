import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/services/profile_service.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/presentation/view/profile_photo_name_page.dart';
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

  /// What the server says when Continue asks about a name; throws if it is an
  /// error (the server can't be reached).
  Object? answer;
  final asked = <String>[];

  @override
  Future<String?> usernameProblem(String username) async {
    asked.add(username);
    final a = answer;
    if (a is Exception) throw a;
    return a as String?;
  }

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

    test('a bad username is reported as it is typed, a good one is not', () {
      viewModel().usernameChanged('ab');
      expect(state().usernameError, isNotNull);
      viewModel().usernameChanged('abc');
      expect(state().usernameError, isNull);
      viewModel().usernameChanged('has space!');
      expect(state().usernameError, isNotNull);
      viewModel().usernameChanged('');
      expect(state().usernameError, isNull, reason: 'empty: one is made');
    });

    test('the @ is not part of the username, and capitals are lowered', () {
      viewModel().usernameChanged('@Bright_Banda');
      expect(state().username, 'bright_banda');
      expect(state().usernameError, isNull);
    });

    test('an invalid username keeps you on this step, with the reason', () {
      viewModel().continueToInterests('Bright', username: 'no-good!');
      expect(state().step, OnboardingStep.photoName);
      expect(state().usernameError, isNotNull);

      viewModel().continueToInterests('Bright', username: 'no_good');
      expect(state().step, OnboardingStep.interests);
      expect(state().usernameError, isNull);
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

  group('Continue checks the username with the server', () {
    late _TakenUsernameProfiles profiles;
    setUp(() {
      profiles = _TakenUsernameProfiles();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          currentAccountIdProvider.overrideWith((ref) => ref.watch(_account)),
          profileServiceProvider.overrideWithValue(profiles),
        ],
      );
    });

    test('a free name goes on to the next step', () async {
      await viewModel().continueFromNames('Bright', username: '@Bright_Banda');
      expect(profiles.asked, ['bright_banda']);
      expect(state().step, OnboardingStep.interests);
      expect(state().usernameError, isNull);
      expect(state().checkingUsername, isFalse);
    });

    test('a taken name stays here and says so', () async {
      profiles.answer = 'That username is already taken. Try another one.';
      await viewModel().continueFromNames('Bright', username: 'bob');
      expect(state().step, OnboardingStep.photoName);
      expect(state().usernameError, contains('already taken'));
      expect(state().checkingUsername, isFalse);
    });

    test('nothing is asked while typing, only when Continue is pressed', () {
      viewModel().usernameChanged('bob');
      expect(profiles.asked, isEmpty);
    });

    test('a name against the rules is not sent to the server', () async {
      await viewModel().continueFromNames('Bright', username: 'no-good!');
      expect(profiles.asked, isEmpty);
      expect(state().step, OnboardingStep.photoName);
      expect(state().usernameError, isNotNull);
    });

    test('no username needs no check', () async {
      await viewModel().continueFromNames('Bright');
      expect(profiles.asked, isEmpty);
      expect(state().step, OnboardingStep.interests);
    });

    test('when the server cannot be reached, you are let through', () async {
      profiles.answer = const ApiException('No connection.');
      await viewModel().continueFromNames('Bright', username: 'bob');
      expect(state().step, OnboardingStep.interests);
    });

    test('a second press while checking does nothing', () async {
      final first = viewModel().continueFromNames('B', username: 'bob');
      await viewModel().continueFromNames('B', username: 'bob');
      await first;
      expect(profiles.asked, hasLength(1));
    });
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

  testWidgets('the username field shows an @, and drops one that is typed', (
    t,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: ProfilePhotoNamePage(
          usernameController: controller,
          usernameError: 'bad',
        ),
      ),
    );
    expect(find.text('@'), findsOneWidget);
    expect(find.text('bad'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '@Bright Banda');
    expect(controller.text, 'brightbanda');
  });
}

class _TestProfileViewModel extends ProfileViewModel {
  @override
  Future<Profile?> build() async => null;
}
