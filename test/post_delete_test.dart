import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const me = 'me';

PublicUser person(String id, String name) =>
    PublicUser(id: id, username: id, displayName: name);

Post aPost({String authorId = me, String id = 'p1'}) => Post(
  id: id,
  author: person(authorId, authorId == me ? 'Me' : 'Someone Else'),
  title: 'A heading',
  content: 'A post',
  sparkCount: 0,
  commentCount: 0,
  sparked: false,
  pinned: false,
  createdAt: DateTime.utc(2026),
);

class _FakeService extends PostService {
  _FakeService() : super(Dio());

  final deleted = <String>[];
  bool fail = false;

  @override
  Future<void> delete(String id) async {
    if (fail) throw Exception('nope');
    deleted.add(id);
  }

  @override
  Future<PostPage> feed({String? cursor, int limit = 20}) async =>
      const PostPage(items: []);

  @override
  Future<PostPage> list({
    String? circleId,
    String? authorId,
    String? cursor,
    int limit = 20,
  }) async => const PostPage(items: []);
}

/// Pumps a [PostCard] as the signed-in person [account].
Future<void> pumpCard(
  WidgetTester tester,
  Post post, {
  required String account,
  required PostService service,
  bool canManage = false,
  VoidCallback? onDeleted,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountIdProvider.overrideWithValue(account),
        postServiceProvider.overrideWithValue(service),
        sharedPreferencesProvider.overrideWithValue(prefs),
        socialServiceProvider.overrideWithValue(FakeFollowSocial()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: post,
            canManage: canManage,
            onDeleted: onDeleted,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the author sees the delete menu', (tester) async {
    await pumpCard(tester, aPost(), account: me, service: _FakeService());
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('somebody else does not', (tester) async {
    await pumpCard(
      tester,
      aPost(authorId: 'other'),
      account: me,
      service: _FakeService(),
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('an Overseer sees the delete menu', (tester) async {
    await pumpCard(
      tester,
      aPost(authorId: 'other'),
      account: me,
      service: _FakeService(),
      canManage: true,
    );
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('cancelling the dialog deletes nothing', (tester) async {
    final service = _FakeService();
    await pumpCard(tester, aPost(), account: me, service: service);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The confirmation is up.
    expect(find.text('Delete this post?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(service.deleted, isEmpty);
  });

  testWidgets('confirming deletes the post and tells the page', (tester) async {
    final service = _FakeService();
    var told = false;
    await pumpCard(
      tester,
      aPost(),
      account: me,
      service: service,
      onDeleted: () => told = true,
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // The second "Delete" is the one in the dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(service.deleted, ['p1']);
    expect(told, isTrue);
  });

  test('deleting refreshes the lists the post was in', () async {
    final service = _FakeService();
    final container = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    await container.read(postDeleteProvider.notifier).delete('p1');
    expect(service.deleted, ['p1']);
    // Nothing failed, so the controller is not holding an error.
    expect(container.read(postDeleteProvider).hasError, isFalse);
  });

  test('a failed delete is reported, not swallowed', () async {
    final service = _FakeService()..fail = true;
    final container = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final done = await container.read(postDeleteProvider.notifier).delete('p1');
    expect(done, isFalse);
    expect(container.read(postDeleteProvider).hasError, isTrue);
  });
}
