import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/auth_providers.dart';

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

Future<void> _show(WidgetTester t, Post post, {bool full = false}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [currentAccountIdProvider.overrideWithValue('me')],
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

  testWidgets('FOLLOW becomes FOLLOWING once you follow, and is hidden on '
      'your own posts', (t) async {
    await _show(t, _post());
    expect(find.text('FOLLOW'), findsOneWidget);

    await _show(t, _post(following: true));
    expect(find.text('FOLLOWING'), findsOneWidget);
    expect(find.text('FOLLOW'), findsNothing);

    await _show(t, _post(author: 'me'));
    expect(find.text('FOLLOW'), findsNothing);
    expect(find.text('FOLLOWING'), findsNothing);
  });
}
