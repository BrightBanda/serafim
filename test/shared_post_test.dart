import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/presentation/view/widgets/shared_post_card.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Post _post({
  String? title = 'Weekend hike',
  String content = 'Who is in?',
  List<String> images = const [],
  Map<String, dynamic>? circle,
}) => Post.fromJson({
  'id': 'p1',
  'author': {'id': 'u1', 'username': 'ann', 'display_name': 'Ann'},
  'title': title,
  'content': content,
  'image_urls': images,
  if (circle != null) 'circle': circle,
});

Future<void> _showCard(WidgetTester t, Future<Post> Function() load) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      retry: noAutoRetry, // as in the app: a failure shows at once
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        sharedPreferencesProvider.overrideWithValue(prefs),
        socialServiceProvider.overrideWithValue(FakeFollowSocial()),
        postProvider.overrideWith((ref, id) => load()),
        postCommentsProvider.overrideWith((ref, id) async => const []),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SharedPostCard(postId: 'p1', outgoing: false)),
      ),
    ),
  );
  await t.pump();
}

void main() {
  group('a post shared in a chat', () {
    testWidgets('shows its heading, author and Circle, and a picture preview', (
      t,
    ) async {
      await _showCard(
        t,
        () async => _post(
          images: ['https://storage.example/u1/a.jpg', 'https://x/b.jpg'],
          circle: {'id': 'c1', 'name': 'Hikers'},
        ),
      );
      expect(find.text('Weekend hike'), findsOneWidget);
      expect(find.text('Ann · Hikers'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget, reason: 'one more picture');
      // The picture is shown, never its address.
      expect(find.textContaining('https://'), findsNothing);
    });

    test('a post without a heading is named by its first line', () {
      expect(
        SharedPostCard.headingOf(_post(title: null, content: 'Hi\nthere')),
        'Hi',
      );
      expect(
        SharedPostCard.headingOf(
          _post(title: null, content: '', images: ['u']),
        ),
        'Photo',
      );
    });

    testWidgets('one the reader may not see is not shown', (t) async {
      await _showCard(t, () async => throw const ApiException('Not found.'));
      expect(find.textContaining("isn't available"), findsOneWidget);
    });

    testWidgets('tapping it opens the post', (t) async {
      await _showCard(t, () async => _post());
      await t.tap(find.byKey(const ValueKey('shared-post-p1')));
      await t.pumpAndSettle();
      expect(find.byType(PostDetailPage), findsOneWidget);
    });
  });

  group('a post with several pictures', () {
    Future<void> showImages(WidgetTester t, List<String> urls) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 360, child: PostImages(urls: urls)),
          ),
        ),
      );
      await t.pump();
    }

    testWidgets('says how many there are and which one is showing', (t) async {
      await showImages(t, ['a', 'b', 'c']);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.byKey(const ValueKey('post-image-dots')), findsOneWidget);

      await t.drag(
        find.byKey(const ValueKey('post-images')),
        const Offset(-300, 0),
      );
      await t.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('the next picture peeks in from the edge', (t) async {
      await showImages(t, ['a', 'b']);
      expect(PostImages.viewportFraction, lessThan(1));
      // Part of the second picture is already laid out on screen.
      expect(find.byType(GestureDetector).evaluate().length, greaterThan(1));
    });

    testWidgets('a single picture has no counter', (t) async {
      await showImages(t, ['a']);
      expect(find.text('1/1'), findsNothing);
      expect(find.byKey(const ValueKey('post-image-dots')), findsNothing);
    });
  });
}
