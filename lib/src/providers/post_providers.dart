import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final postServiceProvider = Provider<PostService>(
  (ref) => PostService(ref.watch(apiDioProvider)),
);

/// A list of posts that grows as the person asks for more. Subclasses say
/// where the posts come from; [loadMore] appends the next page.
abstract class PagedPosts extends AsyncNotifier<PostPage> {
  bool _loadingMore = false;

  Future<PostPage> fetch(String? cursor);

  @override
  Future<PostPage> build() => fetch(null);

  /// Appends the next page. Does nothing while one is already coming, or when
  /// there are no more. A failure leaves the posts already shown in place.
  Future<void> loadMore() async {
    final current = state.value;
    if (_loadingMore || current == null || !current.hasMore) return;
    _loadingMore = true;
    try {
      final next = await fetch(current.nextCursor);
      state = AsyncData(
        PostPage(
          items: [...current.items, ...next.items],
          nextCursor: next.nextCursor,
        ),
      );
    } catch (_) {
      // The button is still there to try again.
    } finally {
      _loadingMore = false;
    }
  }
}

/// A Circle's posts.
class CirclePosts extends PagedPosts {
  CirclePosts(this.circleId);

  final String circleId;

  @override
  Future<PostPage> fetch(String? cursor) =>
      ref.read(postServiceProvider).list(circleId: circleId, cursor: cursor);
}

final circlePostsProvider =
    AsyncNotifierProvider.family<CirclePosts, PostPage, String>(
      CirclePosts.new,
    );

/// Someone's profile posts.
class AuthorPosts extends PagedPosts {
  AuthorPosts(this.authorId);

  final String authorId;

  @override
  Future<PostPage> fetch(String? cursor) =>
      ref.read(postServiceProvider).list(authorId: authorId, cursor: cursor);
}

final authorPostsProvider =
    AsyncNotifierProvider.family<AuthorPosts, PostPage, String>(
      AuthorPosts.new,
    );

/// The signed-in person's feed.
class FeedPosts extends PagedPosts {
  @override
  Future<PostPage> fetch(String? cursor) async {
    if (ref.watch(currentAccountIdProvider) == null) {
      return const PostPage(items: []);
    }
    return ref.read(postServiceProvider).feed(cursor: cursor);
  }
}

final feedProvider = AsyncNotifierProvider<FeedPosts, PostPage>(FeedPosts.new);

/// One post by id.
final postProvider = FutureProvider.family<Post, String>((ref, id) async {
  return ref.watch(postServiceProvider).detail(id);
});

/// The comments on a post, oldest first.
final postCommentsProvider = FutureProvider.family<List<PostComment>, String>((
  ref,
  postId,
) async {
  return ref.watch(postServiceProvider).comments(postId);
});

/// Posts something, and refreshes whatever list it appears in.
class PostComposerController extends AsyncNotifier<Post?> {
  @override
  Future<Post?> build() async => null;

  /// Posts to a Circle, or to your own profile when [circleId] is null.
  Future<Post?> post({
    required String title,
    required String content,
    String? circleId,
    List<String> imageUrls = const [],
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final created = await ref
          .read(postServiceProvider)
          .create(
            title: title,
            content: content,
            circleId: circleId,
            imageUrls: imageUrls,
          );
      ref.invalidate(feedProvider);
      if (circleId != null) {
        ref.invalidate(circlePostsProvider(circleId));
      }
      // The profile's own list of posts has to refresh too, or a post you
      // just wrote does not appear on your profile until you pull to refresh.
      ref.invalidate(authorPostsProvider);
      ref.invalidate(postImageQuotaProvider);
      return created;
    });
    state = result;
    return result.value;
  }
}

final postComposerProvider =
    AsyncNotifierProvider<PostComposerController, Post?>(
      PostComposerController.new,
    );

/// How many pictures the person has shared today, and how many are left.
///
/// Re-read after each post, so the counter on the composer stays true.
final postImageQuotaProvider = FutureProvider.autoDispose<ImageQuota>((
  ref,
) async {
  if (ref.watch(currentAccountIdProvider) == null) {
    return const ImageQuota(used: 0, limit: PostLimits.dailyImagesMax);
  }
  return ref.watch(postServiceProvider).imageQuota();
});

/// Deletes a post, and refreshes every list it was in.
class PostDeleteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> delete(String postId) async {
    var done = false;
    state = await AsyncValue.guard(() async {
      await ref.read(postServiceProvider).delete(postId);
      done = true;
      ref.invalidate(feedProvider);
      ref.invalidate(authorPostsProvider);
      ref.invalidate(circlePostsProvider);
      ref.invalidate(postProvider(postId));
    });
    return done;
  }
}

final postDeleteProvider = AsyncNotifierProvider<PostDeleteController, void>(
  PostDeleteController.new,
);

/// Comments on a post, or replies to another comment.
class CommentController extends AsyncNotifier<PostComment?> {
  @override
  Future<PostComment?> build() async => null;

  Future<PostComment?> comment(
    String postId, {
    required String content,
    String? parentId,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final created = await ref
          .read(postServiceProvider)
          .comment(postId, content: content, parentId: parentId);
      ref.invalidate(postCommentsProvider(postId));
      return created;
    });
    state = result;
    return result.value;
  }
}

final commentProvider = AsyncNotifierProvider<CommentController, PostComment?>(
  CommentController.new,
);

/// What the screen shows for a post or comment you have just sparked (or
/// un-sparked), before the server has answered. Keyed `p:<post id>` and
/// `c:<comment id>`; when there is no entry, the post's own numbers are shown.
typedef SparkView = ({bool sparked, int count});

class SparkOverrides extends Notifier<Map<String, SparkView>> {
  @override
  Map<String, SparkView> build() => const {};

  void set(String key, SparkView view) => state = {...state, key: view};

  void clear() => state = const {};
}

final sparkOverridesProvider =
    NotifierProvider<SparkOverrides, Map<String, SparkView>>(
      SparkOverrides.new,
    );

/// Sparks a post or comment, or takes the Spark back.
///
/// Optimistic: the bolt and the count change the instant you tap, and the
/// request follows. When the server answers, its number replaces ours; if the
/// request fails, the old state comes back. Quick repeated taps are folded
/// into one request for the last thing you asked for.
class SparkController extends AsyncNotifier<void> {
  /// What the person last asked for, per key, while a request is running.
  final Map<String, bool> _wanted = {};

  @override
  Future<void> build() async {}

  Future<void> togglePost(Post post, {required bool on}) => _toggle(
    'p:${post.id}',
    (sparked: post.sparked, count: post.sparkCount),
    on,
    (want) => ref.read(postServiceProvider).sparkPost(post.id, on: want),
  );

  Future<void> toggleComment(PostComment comment, {required bool on}) =>
      _toggle(
        'c:${comment.id}',
        (sparked: comment.sparked, count: comment.sparkCount),
        on,
        (want) =>
            ref.read(postServiceProvider).sparkComment(comment.id, on: want),
      );

  Future<void> _toggle(
    String key,
    SparkView base,
    bool on,
    Future<SparkResult> Function(bool want) send,
  ) async {
    final overrides = ref.read(sparkOverridesProvider.notifier);
    final shown = ref.read(sparkOverridesProvider)[key] ?? base;
    if (shown.sparked == on) return;

    // Show it now.
    overrides.set(key, (
      sparked: on,
      count: (shown.count + (on ? 1 : -1)).clamp(0, 1 << 30),
    ));

    final running = _wanted.containsKey(key);
    _wanted[key] = on;
    if (running) return; // the running request will pick up the latest wish

    var confirmed = shown;
    try {
      while (true) {
        final want = _wanted[key]!;
        if (want == confirmed.sparked) break;
        final result = await send(want);
        confirmed = (sparked: result.sparked, count: result.sparkCount);
        // Only show the server's number if nothing newer was asked for.
        if (_wanted[key] == want) overrides.set(key, confirmed);
        if (_wanted[key] == want) break;
      }
      state = const AsyncData(null);
    } catch (error, stack) {
      overrides.set(key, confirmed); // put the old state back
      state = AsyncError(error, stack);
    } finally {
      _wanted.remove(key);
    }
  }
}

final sparkProvider = AsyncNotifierProvider<SparkController, void>(
  SparkController.new,
);

/// Pins a post to the top of its Circle, or takes the pin off.
class PinController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> toggle(
    String postId, {
    required bool on,
    String? circleId,
  }) async {
    state = await AsyncValue.guard(() async {
      final service = ref.read(postServiceProvider);
      if (on) {
        await service.pin(postId);
      } else {
        await service.unpin(postId);
      }
      if (circleId != null) {
        ref.invalidate(circlePostsProvider(circleId));
      } else {
        ref.invalidate(feedProvider);
      }
    });
  }
}

final pinProvider = AsyncNotifierProvider<PinController, void>(
  PinController.new,
);
