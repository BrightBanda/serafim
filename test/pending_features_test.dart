import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/config/profile_limits.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/notification_service.dart';
import 'package:serafim/src/data/services/official_service.dart';
import 'package:serafim/src/data/services/social_service.dart';
import 'package:serafim/src/presentation/view/main_screen.dart';
import 'package:serafim/src/presentation/view/notifications_page.dart';
import 'package:serafim/src/presentation/view/official_chat_page.dart';
import 'package:serafim/src/presentation/view/profile_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/notification_providers.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/providers/relation_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/in_app_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = 'me';

PublicUser person(String id, {bool following = false, int? followers}) =>
    PublicUser(
      id: id,
      username: id,
      displayName: id.toUpperCase(),
      isFollowing: following,
      followerCount: followers,
    );

/// A social backend whose answers the test releases by hand.
class FakeSocial extends SocialService {
  FakeSocial() : super(Dio());

  final calls = <String>[];
  final pending = <Completer<Object?>>[];

  Future<T> _wait<T>(String call) {
    calls.add(call);
    final c = Completer<Object?>();
    pending.add(c);
    return c.future.then((v) => v as T);
  }

  void answer([Object? value]) => pending.removeAt(0).complete(value);
  void fail(String message) =>
      pending.removeAt(0).completeError(ApiException(message));

  @override
  Future<FriendStatus> sendRequest(String userId) => _wait('request $userId');
  @override
  Future<void> follow(String userId) => _wait('follow $userId');
  @override
  Future<void> unfollow(String userId) => _wait('unfollow $userId');
}

Future<ProviderContainer> container({
  SocialService? social,
  NotificationService? notifications,
  OfficialService? official,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localCacheProvider.overrideWithValue(LocalCache(prefs)),
      currentAccountIdProvider.overrideWithValue(me),
      if (social != null) socialServiceProvider.overrideWithValue(social),
      if (notifications != null)
        notificationServiceProvider.overrideWithValue(notifications),
      if (official != null) officialServiceProvider.overrideWithValue(official),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('optimistic friend and follow actions', () {
    test(
      'a friend request shows as sent at once and rolls back on failure',
      () async {
        final social = FakeSocial();
        final c = await container(social: social);
        final actions = c.read(socialActionsProvider);

        final result = actions.sendRequest('bob');
        expect(
          c.read(relationOverridesProvider).friend['bob'],
          FriendStatus.requestSent,
        );

        // A second tap while the first is on its way sends nothing more.
        expect(await actions.sendRequest('bob'), isNull);
        expect(social.calls, ['request bob']);

        social.fail('This user is not accepting friend requests.');
        expect(await result, 'This user is not accepting friend requests.');
        expect(c.read(relationOverridesProvider).friend, isEmpty);
      },
    );

    test(
      'the server answer replaces the guess, then server data takes over',
      () async {
        final social = FakeSocial();
        final c = await container(social: social);
        final result = c.read(socialActionsProvider).sendRequest('bob');

        // They had already asked us, so the server made us friends.
        social.answer(FriendStatus.friends);
        await settle();
        expect(await result, isNull);
        expect(c.read(relationOverridesProvider).friend, isEmpty);
      },
    );

    test('rapid follow taps are coalesced into the fewest requests', () async {
      final social = FakeSocial();
      final c = await container(social: social);
      final actions = c.read(socialActionsProvider);

      final first = actions.follow('bob');
      expect(c.read(relationOverridesProvider).follow['bob'], isTrue);
      // Unfollow, follow, unfollow while the first request is in flight.
      expect(await actions.unfollow('bob'), isNull);
      expect(await actions.follow('bob'), isNull);
      expect(await actions.unfollow('bob'), isNull);
      expect(c.read(relationOverridesProvider).follow['bob'], isFalse);

      social.answer(); // follow done; latest wish is "not following"
      await settle();
      expect(social.calls, ['follow bob', 'unfollow bob']);
      social.answer();
      expect(await first, isNull);
      expect(social.calls, ['follow bob', 'unfollow bob']);
      expect(c.read(relationOverridesProvider).follow, isEmpty);
    });

    test('a failed follow rolls back and reports why', () async {
      final social = FakeSocial();
      final c = await container(social: social);
      final result = c.read(socialActionsProvider).follow('bob');
      social.fail("Can't reach the server.");
      expect(await result, "Can't reach the server.");
      expect(c.read(relationOverridesProvider).follow, isEmpty);
    });

    test('follower count moves with a pending follow, and only once', () {
      final bob = person('bob', followers: 4);
      final shown = bob.withRelation(isFollowing: true);
      expect(shown.isFollowing, isTrue);
      expect(shown.followerCount, 5);
      expect(shown.withRelation(isFollowing: true).followerCount, 5);
      expect(
        person(
          'x',
          following: true,
          followers: 0,
        ).withRelation(isFollowing: false).followerCount,
        0,
      );
    });
  });

  group('swipe to dismiss notifications', () {
    AppNotification note(String id, {bool read = false}) => AppNotification(
      id: id,
      kind: NotificationKind.newFollower,
      isRead: read,
      createdAt: DateTime.utc(2026, 10, 1),
      actor: person('a$id'),
    );

    test(
      'removed at once; put back in the same place if the server refuses',
      () async {
        final service = _FakeNotifications([note('1'), note('2'), note('3')]);
        final c = await container(notifications: service);
        await c.read(notificationsProvider.future);

        service.deleteError = const ApiException('Server unavailable.');
        final pending = c.read(notificationsProvider.notifier).dismiss('2');
        expect(c.read(notificationsProvider).value!.map((n) => n.id), [
          '1',
          '3',
        ]);
        expect(await pending, 'Server unavailable.');
        expect(c.read(notificationsProvider).value!.map((n) => n.id), [
          '1',
          '2',
          '3',
        ]);
      },
    );

    test('success, or already gone on the server, keeps it removed', () async {
      final service = _FakeNotifications([note('1'), note('2')]);
      final c = await container(notifications: service);
      await c.read(notificationsProvider.future);
      final controller = c.read(notificationsProvider.notifier);

      expect(await controller.dismiss('1'), isNull);
      service.deleteError = const ApiException('gone', statusCode: 404);
      expect(await controller.dismiss('2'), isNull);
      expect(c.read(notificationsProvider).value, isEmpty);
      expect(service.deleted, ['1', '2']);
    });

    test('unread count and mark all read', () async {
      final service = _FakeNotifications([note('1'), note('2', read: true)]);
      final c = await container(notifications: service);
      await c.read(notificationsProvider.future);
      expect(c.read(unreadNotificationCountProvider), 1);
      expect(
        await c.read(notificationsProvider.notifier).markAllRead(),
        isNull,
      );
      expect(c.read(unreadNotificationCountProvider), 0);
    });

    testWidgets('swiping a card removes it from the page', (tester) async {
      final service = _FakeNotifications([note('1'), note('2')]);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          retry: noAutoRetry,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentAccountIdProvider.overrideWithValue(me),
            notificationServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: NotificationsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('A1', findRichText: true), findsOneWidget);
      expect(find.text('NEW · 2 UNREAD'), findsOneWidget);

      await tester.drag(
        find.textContaining('A1', findRichText: true),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('A1', findRichText: true), findsNothing);
      expect(find.textContaining('A2', findRichText: true), findsOneWidget);
      expect(service.deleted, ['1']);
    });
  });

  group('press back twice to exit', () {
    test(
      'a second press within two seconds exits; later presses start over',
      () {
        var now = DateTime(2026);
        final guard = BackToExitGuard(clock: () => now);
        expect(guard.shouldExit(), isFalse);
        now = now.add(const Duration(milliseconds: 1500));
        expect(guard.shouldExit(), isTrue);

        now = now.add(const Duration(seconds: 10));
        expect(guard.shouldExit(), isFalse);
        now = now.add(const Duration(milliseconds: 2500));
        expect(guard.shouldExit(), isFalse, reason: 'window expired: reset');
        now = now.add(const Duration(milliseconds: 300));
        expect(guard.shouldExit(), isTrue);
      },
    );
  });

  group('copyable UID', () {
    testWidgets('copies exactly the UID and confirms', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      const uid = '3f2a9c1e-0000-4abc-9def-1234567890ab';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: UidRow(uid: uid)),
        ),
      );
      await tester.tap(find.byTooltip('Copy UID'));
      await tester.pump();
      expect(copied, uid);
      expect(find.text('UID copied'), findsOneWidget);
    });
  });

  group('profile limits and bio', () {
    test('limits match the server', () {
      expect(ProfileLimits.displayNameError(''), isNotNull);
      expect(ProfileLimits.displayNameError('n' * 30), isNull);
      expect(ProfileLimits.displayNameError('n' * 31), isNotNull);
      expect(ProfileLimits.usernameError('ab'), isNotNull);
      expect(ProfileLimits.usernameError('u' * 20), isNull);
      expect(ProfileLimits.usernameError('u' * 21), isNotNull);
      expect(ProfileLimits.usernameError('Has_Caps'), isNotNull);
      expect(ProfileLimits.bioError('b' * 160), isNull);
      expect(ProfileLimits.bioError('b' * 161), isNotNull);
    });

    test(
      'an empty bio is sent so the server clears it; null leaves it alone',
      () {
        expect(const ProfileUpdateRequest(bio: '').toJson(), {'bio': ''});
        expect(const ProfileUpdateRequest(displayName: 'A').toJson(), {
          'display_name': 'A',
        });
        expect(const ProfileUpdateRequest(lockProfile: true).toJson(), {
          'lock_profile': true,
        });
      },
    );

    test('bio and lock survive the saved-copy round trip', () {
      final user = PublicUser.fromJson({
        'id': 'u',
        'username': 'u',
        'display_name': 'U',
        'bio': 'Hello',
        'profile_locked': true,
        'friend_count': 3,
      });
      final back = PublicUser.fromJson(user.toJson());
      expect(back.bio, 'Hello');
      expect(back.profileLocked, isTrue);
      expect(back.friendCount, 3);
    });
  });

  group('official SERAFIM chat', () {
    test(
      'live announcements are merged without duplicates, newest first',
      () async {
        final official = _FakeOfficial([
          Announcement(
            id: 'a1',
            content: 'Welcome',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ]);
        final c = await container(official: official);
        final state = await c.read(officialChatProvider.future);
        expect(state.canPost, isFalse);
        expect(c.read(officialUnreadProvider), isTrue);

        final notifier = c.read(officialChatProvider.notifier);
        final next = Announcement(
          id: 'a2',
          content: 'News',
          createdAt: DateTime.utc(2026, 2, 1),
        );
        notifier.receive(next);
        notifier.receive(next); // the socket echo of the same one
        expect(
          c.read(officialChatProvider).value!.announcements.map((a) => a.id),
          ['a2', 'a1'],
        );

        c.read(officialLastReadProvider.notifier).markSeen(next.createdAt);
        expect(c.read(officialUnreadProvider), isFalse);

        notifier.removeLocal('a2');
        expect(c.read(officialChatProvider).value!.latest!.id, 'a1');
      },
    );
  });

  group('official chat page', () {
    testWidgets(
      'opening it and going back does not modify providers mid-build',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final official = _FakeOfficial([
          Announcement(
            id: 'a1',
            content: 'Welcome',
            createdAt: DateTime.utc(2026),
          ),
        ]);
        late ProviderContainer c;
        await tester.pumpWidget(
          ProviderScope(
            retry: noAutoRetry,
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              localCacheProvider.overrideWithValue(LocalCache(prefs)),
              currentAccountIdProvider.overrideWithValue(me),
              officialServiceProvider.overrideWithValue(official),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  c = ProviderScope.containerOf(context);
                  return TextButton(
                    onPressed: () => openOfficialChat(context),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome'), findsOneWidget);
        expect(c.read(activeRoomProvider), officialRoomId);

        Navigator.of(tester.element(find.text('Welcome'))).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(c.read(activeRoomProvider), isNull);
      },
    );
  });

  group('banner', () {
    testWidgets('shows the kind of alert it is', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: key, home: const SizedBox()),
      );
      InAppBannerService(key).show(
        title: 'Sam',
        body: 'Started following you',
        label: 'NEW FOLLOWER',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('NEW FOLLOWER'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}

class _FakeNotifications extends NotificationService {
  _FakeNotifications(this.items) : super(Dio());

  final List<AppNotification> items;
  final deleted = <String>[];
  Object? deleteError;

  @override
  Future<List<AppNotification>> list({int limit = 50}) async => items;

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<void> markRead({List<String>? ids}) async {}
}

class _FakeOfficial extends OfficialService {
  _FakeOfficial(this.items) : super(Dio());

  final List<Announcement> items;

  @override
  Future<OfficialChatInfo> info() async => const OfficialChatInfo(
    name: 'SERAFIM',
    username: 'serafim',
    canPost: false,
  );

  @override
  Future<List<Announcement>> announcements({
    DateTime? before,
    int limit = 50,
  }) async => items;
}
