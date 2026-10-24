import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/presentation/view/settings_page.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_list_providers.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class _NoProfile extends ProfileViewModel {
  @override
  FutureOr<Profile?> build() => null;
}

Post _post({
  int sparks = 0,
  int comments = 0,
  String? title = 'Heading',
  Map<String, dynamic>? circle,
  List<String> images = const [],
}) => Post.fromJson({
  'id': 'p1',
  'author': {'id': 'u1', 'username': 'ann', 'display_name': 'Ann'},
  'title': title,
  'content': 'Body text',
  'spark_count': sparks,
  'comment_count': comments,
  'image_urls': images,
  if (circle != null) 'circle': circle,
});

void main() {
  group('Circle notifications', () {
    Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
      'id': 'n1',
      'type': 'circle_post_commented',
      'created_at': '2026-10-01T10:00:00Z',
      'actor': {'id': 'u2', 'username': 'bo', 'display_name': 'Bo'},
      ...extra,
    };

    test('carry the Circle and post they are about', () {
      final n = AppNotification.fromJson(
        json({'circle_id': 'c9', 'post_id': 42}),
      );
      expect(n.circleId, 'c9');
      expect(n.postId, '42');
    });

    test('also read the ids from a nested data map', () {
      final n = AppNotification.fromJson(
        json({
          'data': {'circle_id': 'c9', 'post_id': 'p7'},
        }),
      );
      expect([n.circleId, n.postId], ['c9', 'p7']);
    });

    test('posts, comments, replies and Sparks have their own words', () {
      final cases = {
        'friend_posted': 'Bo shared a new post',
        'circle_new_post': 'Bo posted in a Circle you are in',
        'post_commented': 'Bo commented on your post',
        'comment_replied': 'Bo replied to your comment',
        'post_sparked': 'Bo sparked your post',
        'comment_sparked': 'Bo sparked your comment',
      };
      for (final MapEntry(key: type, value: text) in cases.entries) {
        final n = AppNotification.fromJson(
          json({'type': type, 'post_id': 'p1'}),
        );
        expect(n.kind, isNot(NotificationKind.unknown), reason: type);
        expect(n.text, text);
        // All of them open the post they are about.
        expect(n.kind.isAboutPost, isTrue, reason: type);
        expect(n.postId, 'p1');
      }
      expect(NotificationKind.friendRequest.isAboutPost, isFalse);
      expect(NotificationKind.postSparked.bannerLabel, 'SPARKS');
      expect(NotificationKind.friendPosted.bannerLabel, 'NEW POST');
    });

    test('are fine without them (older servers)', () {
      final n = AppNotification.fromJson(json());
      expect([n.circleId, n.postId], [null, null]);
      expect(n.copyWith(isRead: true).circleId, isNull);
    });
  });

  group('post actions', () {
    test('counts are followed by what they count', () {
      expect(countLabel(0, 'Spark'), 'Spark');
      expect(countLabel(1, 'Spark'), '1 Spark');
      expect(countLabel(12, 'Comment'), '12 Comments');
    });

    testWidgets('the card shows Spark, Comment and Share', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentAccountIdProvider.overrideWithValue('me'),
            sharedPreferencesProvider.overrideWithValue(prefs),
            socialServiceProvider.overrideWithValue(FakeFollowSocial()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320, // A narrow phone: wraps rather than overflows.
                child: PostCard(post: _post(sparks: 1234, comments: 5678)),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('1234 Sparks'), findsOneWidget);
      expect(find.text('5678 Comments'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });
  });

  group('profile menu', () {
    Future<void> openMenu(WidgetTester t, {bool showProfile = true}) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            profileViewModelProvider.overrideWith(_NoProfile.new),
            myHaloLitProvider.overrideWith((ref) => false),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [ProfileMenuButton(showProfile: showProfile)],
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byType(ProfileMenuButton));
      await t.pumpAndSettle();
    }

    testWidgets('offers profile, Halo and settings', (t) async {
      await openMenu(t);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Halo'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('on the profile page, only Halo and settings', (t) async {
      await openMenu(t, showProfile: false);
      expect(find.text('Profile'), findsNothing);
      expect(find.text('Halo'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('removed chats', () {
    final at = DateTime.utc(2026, 10, 1, 12);

    test('stay off the list until something newer arrives', () {
      expect(isChatRemoved(null, at), isFalse);
      expect(isChatRemoved(at, null), isTrue);
      expect(isChatRemoved(at, at), isTrue);
      expect(isChatRemoved(at, at.add(const Duration(seconds: 1))), isFalse);
    });

    test('are remembered on the phone, per account', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = LocalCache(await SharedPreferences.getInstance());
      await cache.saveRemovedChats('me', {'me_bo': at});
      expect(cache.removedChats('me'), {'me_bo': at.toLocal()});
      expect(cache.removedChats('someone else'), isEmpty);
    });
  });

  testWidgets('settings has an About section with the version and developer', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          installedVersionProvider.overrideWith(
            (ref) => const AppVersion(name: '1.0.2', code: 3),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('1.0.2 (build 3)'), findsOneWidget);
    expect(find.text('daylight'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
  });
}
