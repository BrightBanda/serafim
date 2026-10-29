import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Post _post({
  String content = 'Hello',
  bool following = false,
  String author = 'u1',
}) => Post.fromJson({
  'id': 'p1',
  'author': {
    'id': author,
    'username': 'a',
    'display_name': 'Ann',
    'is_following': following,
  },
  'title': 'T',
  'content': content,
});

Future<void> _show(
  WidgetTester t,
  Post post, {
  bool full = false,
  FakeFollowSocial? social,
  Map<String, Object> saved = const {},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        sharedPreferencesProvider.overrideWithValue(prefs),
        socialServiceProvider.overrideWithValue(social ?? FakeFollowSocial()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: PostCard(post: post, showFullText: full),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

/// Two posts by the same author, to check they agree.
Future<void> _showTwo(WidgetTester t, FakeFollowSocial social) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        sharedPreferencesProvider.overrideWithValue(prefs),
        socialServiceProvider.overrideWithValue(social),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PostCard(post: _post()),
              PostCard(post: _post()),
            ],
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  final long = List.generate(30, (i) => 'line $i of a long post').join('\n');

  testWidgets('short text has no See more', (t) async {
    await _show(t, _post());
    expect(find.text('See more'), findsNothing);
  });

  testWidgets('long text stops at five lines with See more, which opens it', (
    t,
  ) async {
    await _show(t, _post(content: long));
    expect(find.text('See more'), findsOneWidget);
    final text = t.widget<Text>(find.text(long));
    expect(text.maxLines, 5);

    await t.tap(find.text('See more'));
    await t.pump();
    expect(find.text('See less'), findsOneWidget);
    expect(t.widget<Text>(find.text(long)).maxLines, isNull);
  });

  testWidgets('a post page shows the whole text', (t) async {
    await _show(t, _post(content: long), full: true);
    expect(find.text('See more'), findsNothing);
  });

  testWidgets('tapping the author name opens their profile', (t) async {
    await _show(t, _post());

    await t.tap(find.text('Ann'));
    await t.pumpAndSettle();

    expect(find.byType(UserProfilePage), findsOneWidget);
  });

  testWidgets('tapping the author photo opens their profile', (t) async {
    await _show(t, _post());

    await t.tap(find.byKey(const ValueKey('post-author-avatar-u1')));
    await t.pumpAndSettle();

    expect(find.byType(UserProfilePage), findsOneWidget);
  });

  group('Follow button', () {
    testWidgets('shows what your following list says, not the post', (t) async {
      // The post was loaded saying "not following" (or the server left it
      // out), but you do follow them.
      await _show(t, _post(), social: FakeFollowSocial(['u1']));
      await t.pumpAndSettle();
      expect(find.text('FOLLOWING'), findsOneWidget);
      expect(find.text('FOLLOW'), findsNothing);

      await _show(t, _post(following: true), social: FakeFollowSocial());
      await t.pumpAndSettle();
      expect(find.text('FOLLOW'), findsOneWidget);
    });

    testWidgets('never shows FOLLOW first for someone you follow', (t) async {
      final social = FakeFollowSocial(['u1'])..listGate = Completer<void>();
      await _show(t, _post(), social: social);
      // The list has not arrived: no button rather than a wrong one.
      expect(find.text('FOLLOW'), findsNothing);
      expect(find.text('FOLLOWING'), findsNothing);

      social.listGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('FOLLOWING'), findsOneWidget);
    });

    testWidgets('the list saved on the phone labels it before the network', (
      t,
    ) async {
      final social = FakeFollowSocial(['u1'])..listGate = Completer<void>();
      await _show(
        t,
        _post(),
        social: social,
        saved: {'cache.v1.me.followingIds': '["u1"]'},
      );
      expect(find.text('FOLLOWING'), findsOneWidget);
      social.listGate!.complete();
      await t.pumpAndSettle();
    });

    testWidgets('FOLLOW -> FOLLOWING -> FOLLOW, and it sticks', (t) async {
      final social = FakeFollowSocial();
      await _show(t, _post(), social: social);
      await t.pumpAndSettle();

      await t.tap(find.text('FOLLOW'));
      await t.pump();
      expect(find.text('FOLLOWING'), findsOneWidget); // At once.
      await t.pumpAndSettle();
      // Confirmed by the server and the list refetched: still following.
      expect(find.text('FOLLOWING'), findsOneWidget);
      expect(social.followed, {'u1'});

      await t.tap(find.text('FOLLOWING'));
      await t.pump();
      expect(find.text('FOLLOW'), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text('FOLLOW'), findsOneWidget);
      expect(social.followed, isEmpty);
      expect(social.calls, ['follow u1', 'unfollow u1']);
    });

    testWidgets('every post by the author changes together', (t) async {
      await _showTwo(t, FakeFollowSocial());
      expect(find.text('FOLLOW'), findsNWidgets(2));
      await t.tap(find.text('FOLLOW').first);
      await t.pumpAndSettle();
      expect(find.text('FOLLOWING'), findsNWidgets(2));
    });

    testWidgets('a refused follow goes back and says why', (t) async {
      final social = FakeFollowSocial()..failNext = 'You cannot follow them.';
      await _show(t, _post(), social: social);
      await t.pumpAndSettle();

      await t.tap(find.text('FOLLOW'));
      await t.pumpAndSettle();
      expect(find.text('FOLLOW'), findsOneWidget);
      expect(find.text('You cannot follow them.'), findsOneWidget);
    });

    testWidgets('is hidden on your own posts', (t) async {
      await _show(t, _post(author: 'me'));
      await t.pumpAndSettle();
      expect(find.text('FOLLOW'), findsNothing);
      expect(find.text('FOLLOWING'), findsNothing);
    });
  });
}
