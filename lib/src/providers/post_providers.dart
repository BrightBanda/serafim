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
    required String content,
    String? circleId,
    List<String> imageUrls = const [],
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final created = await ref
          .read(postServiceProvider)
          .create(content: content, circleId: circleId, imageUrls: imageUrls);
      ref.invalidate(feedProvider);
      if (circleId != null) {
        ref.invalidate(circlePostsProvider(circleId));
      }
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

/// Sparks a post, or takes the Spark back.
///
/// The count comes back from the server, so the number on screen is the
/// server's number and not a guess.
class SparkController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> togglePost(String postId, {required bool on}) => _run(
    postId,
    () => ref.read(postServiceProvider).sparkPost(postId, on: on),
  );

  Future<void> toggleComment(String commentId, {required bool on}) => _run(
    commentId,
    () => ref.read(postServiceProvider).sparkComment(commentId, on: on),
  );

  Future<void> _run(String id, Future<Object?> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      // The posts and comments on screen carry their own counts, so they
      // have to be re-read for the number to change.
      ref.invalidate(circlePostsProvider);
      ref.invalidate(authorPostsProvider);
      ref.invalidate(feedProvider);
      ref.invalidate(postCommentsProvider);
      ref.invalidate(postProvider);
    });
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
