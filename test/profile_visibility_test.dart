import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

PublicUser bob({bool locked = false, int? friends}) => PublicUser(
  id: 'bob',
  username: 'bob',
  displayName: 'Bob',
  profileLocked: locked,
  friendCount: friends,
  followerCount: friends,
  followingCount: friends,
);

Future<void> pumpProfile(
  WidgetTester tester,
  PublicUser user, {
  String me = 'me',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutoRetry,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentAccountIdProvider.overrideWithValue(me),
        publicUserProvider.overrideWith((ref, id) async => user),
        knownPersonProvider.overrideWith((ref, id) => null),
      ],
      child: MaterialApp(home: UserProfilePage(userId: user.id)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a locked profile shows a clear locked state to non-friends', (
    tester,
  ) async {
    await pumpProfile(tester, bob(locked: true));
    expect(find.text('This profile is locked'), findsOneWidget);
    expect(find.text('FOLLOWERS'), findsNothing);
  });

  testWidgets(
    'friends of a locked profile see the lists (the server sent counts)',
    (tester) async {
      await pumpProfile(tester, bob(locked: true, friends: 2));
      expect(find.text('This profile is locked'), findsNothing);
      expect(find.text('FRIENDS'), findsOneWidget);
      expect(find.text('FOLLOWERS'), findsOneWidget);
    },
  );

  testWidgets('an unlocked profile shows friends, followers and following', (
    tester,
  ) async {
    await pumpProfile(tester, bob(friends: 0));
    expect(find.text('FOLLOWING'), findsOneWidget);
  });

  group('full-screen photo', viewerTests);

  testWidgets('you always see your own lists', (tester) async {
    await pumpProfile(tester, bob(locked: true), me: 'bob');
    expect(find.text('This profile is locked'), findsNothing);
    expect(find.text('FRIENDS'), findsOneWidget);
  });
}

// ---- full-screen profile photo -------------------------------------------

Future<void> pumpAvatar(WidgetTester tester) => tester.pumpWidget(
  const MaterialApp(
    home: Scaffold(
      body: Center(
        child: TappableAvatar(
          image: null,
          heroTag: 't:1',
          name: 'Ada Lovelace',
        ),
      ),
    ),
  ),
);

void viewerTests() {
  testWidgets(
    'tapping an avatar opens the viewer; a placeholder when no photo',
    (tester) async {
      await pumpAvatar(tester);
      await tester.tap(find.byType(TappableAvatar));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePhotoViewer), findsOneWidget);
      expect(find.text('AL'), findsOneWidget);
      expect(find.text('No photo yet'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Tap closes it.
      await tester.tap(find.text('AL'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePhotoViewer), findsNothing);
    },
  );

  testWidgets('a swipe down closes it; a short drag springs back', (
    tester,
  ) async {
    await pumpAvatar(tester);
    await tester.tap(find.byType(TappableAvatar));
    await tester.pumpAndSettle();

    await tester.drag(find.text('AL'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePhotoViewer), findsOneWidget);

    await tester.drag(find.text('AL'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePhotoViewer), findsNothing);
  });

  test('initials', () {
    expect(initialsOf('ada lovelace byron'), 'AL');
    expect(initialsOf('  '), '?');
    expect(initialsOf('Zed'), 'Z');
  });
}
