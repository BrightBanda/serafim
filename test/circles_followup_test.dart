import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:dio/dio.dart';

Map<String, dynamic> _post(String id) => {
  'id': id,
  'author': {'id': 'u1', 'username': 'a', 'display_name': 'A'},
  'content': 'hi',
};

class _FakeService extends PostService {
  _FakeService() : super(Dio());
  final cursors = <String?>[];

  @override
  Future<PostPage> list({
    String? circleId,
    String? authorId,
    String? cursor,
    int limit = 20,
  }) async {
    cursors.add(cursor);
    return cursor == null
        ? PostPage.fromJson({
            'items': [_post('1')],
            'next_cursor': 'c1',
          })
        : PostPage.fromJson({
            'items': [_post('2')],
          });
  }
}

void main() {
  sparkTests();
  test('circle notification types are recognised', () {
    for (final t in [
      'circle_join_request',
      'circle_request_approved',
      'circle_request_rejected',
      'circle_post_commented',
      'circle_comment_replied',
      'circle_mention',
      'circle_post_pinned',
      'circle_role_changed',
      'circle_banned',
    ]) {
      final kind = NotificationKind.parse(t);
      expect(kind, isNot(NotificationKind.unknown), reason: t);
      expect(kind.isCircle, isTrue, reason: t);
    }
    expect(NotificationKind.friendRequest.isCircle, isFalse);
  });

  test('loadMore appends the next page and stops at the end', () async {
    final fake = _FakeService();
    final container = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    var page = await container.read(circlePostsProvider('c').future);
    expect(page.items.map((p) => p.id), ['1']);
    expect(page.hasMore, isTrue);

    await container.read(circlePostsProvider('c').notifier).loadMore();
    page = container.read(circlePostsProvider('c')).value!;
    expect(page.items.map((p) => p.id), ['1', '2']);
    expect(page.hasMore, isFalse);

    await container.read(circlePostsProvider('c').notifier).loadMore();
    expect(fake.cursors, [null, 'c1']);
  });

  test('a post carries up to four picture links', () {
    final post = Post.fromJson({
      ..._post('1'),
      'image_urls': ['a', 'b'],
    });
    expect(post.imageUrls, ['a', 'b']);
    expect(Post.fromJson(_post('2')).imageUrls, isEmpty);
    expect(PostLimits.imagesMax, 4);
    expect(PostLimits.imageBytesMax, 2 * 1024 * 1024);
  });
}

class _SparkService extends PostService {
  _SparkService() : super(Dio());
  final calls = <bool>[];
  bool fail = false;

  @override
  Future<SparkResult> sparkPost(String postId, {required bool on}) async {
    calls.add(on);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (fail) throw Exception('offline');
    return SparkResult(sparked: on, sparkCount: on ? 6 : 5, postId: postId);
  }
}

void sparkTests() {
  Post sample() => Post.fromJson({..._post('9'), 'spark_count': 5});

  test('a Spark shows at once, then takes the server count', () async {
    final fake = _SparkService();
    final c = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(c.dispose);

    final done = c.read(sparkProvider.notifier).togglePost(sample(), on: true);
    // Before the server has answered:
    expect(c.read(sparkOverridesProvider)['p:9'], (sparked: true, count: 6));
    await done;
    expect(fake.calls, [true]);
    expect(c.read(sparkOverridesProvider)['p:9'], (sparked: true, count: 6));
  });

  test('a failed Spark goes back to how it was', () async {
    final fake = _SparkService()..fail = true;
    final c = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(c.dispose);

    await c.read(sparkProvider.notifier).togglePost(sample(), on: true);
    expect(c.read(sparkOverridesProvider)['p:9'], (sparked: false, count: 5));
    expect(c.read(sparkProvider).hasError, isTrue);
  });

  test('tapping twice quickly sends the last wish, not two guesses', () async {
    final fake = _SparkService();
    final c = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(c.dispose);
    final post = sample();
    final n = c.read(sparkProvider.notifier);

    final first = n.togglePost(post, on: true);
    final second = n.togglePost(post, on: false); // changed their mind
    expect(c.read(sparkOverridesProvider)['p:9'], (sparked: false, count: 5));
    await Future.wait([first, second]);
    expect(c.read(sparkOverridesProvider)['p:9']?.sparked, isFalse);
  });
}
