import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/post.dart';

/// Talks to the backend's `/posts` and `/feed` routes.
class PostService {
  const PostService(this._dio);

  final Dio _dio;

  /// A page of posts: a Circle's, or someone's profile.
  Future<PostPage> list({
    String? circleId,
    String? authorId,
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _call(
      () => _dio.get<dynamic>(
        '/posts',
        queryParameters: {
          if (circleId != null) 'circle_id': circleId,
          if (authorId != null) 'author_id': authorId,
          if (cursor != null) 'cursor': cursor,
          'limit': limit,
        },
      ),
    );
    if (data is! Map<String, dynamic>) throw _unexpected;
    return PostPage.fromJson(data);
  }

  /// The signed-in person's feed: people they follow, Circles they have
  /// joined, and their own posts.
  Future<PostPage> feed({String? cursor, int limit = 20}) async {
    final data = await _call(
      () => _dio.get<dynamic>(
        '/feed',
        queryParameters: {if (cursor != null) 'cursor': cursor, 'limit': limit},
      ),
    );
    if (data is! Map<String, dynamic>) throw _unexpected;
    return PostPage.fromJson(data);
  }

  /// Posts to a Circle, or to your own profile when [circleId] is null.
  Future<Post> create({
    required String content,
    String? circleId,
    List<String> imageUrls = const [],
  }) async =>
      Post.fromJson(
        await _map(
          () => _dio.post<dynamic>(
            '/posts',
            data: {
              'content': content,
              if (circleId != null) 'circle_id': circleId,
              if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
            },
          ),
        ),
      );

  Future<Post> detail(String id) async =>
      Post.fromJson(await _map(() => _dio.get<dynamic>('/posts/$id')));

  Future<void> delete(String id) =>
      _call(() => _dio.delete<dynamic>('/posts/$id'));

  Future<Post> pin(String id) async =>
      Post.fromJson(await _map(() => _dio.put<dynamic>('/posts/$id/pin')));

  Future<Post> unpin(String id) async =>
      Post.fromJson(await _map(() => _dio.delete<dynamic>('/posts/$id/pin')));

  Future<List<PostComment>> comments(String postId) async {
    final data = await _call(
      () => _dio.get<dynamic>(
        '/posts/$postId/comments',
        // The server returns up to 200 at once and has no cursor for comments.
        queryParameters: {'limit': 200},
      ),
    );
    if (data is! Map<String, dynamic>) throw _unexpected;
    final items = data['items'] as List? ?? const [];
    return [
      for (final c in items) PostComment.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// Comments on a post, or replies to another comment.
  Future<PostComment> comment(
    String postId, {
    required String content,
    String? parentId,
  }) async => PostComment.fromJson(
    await _map(
      () => _dio.post<dynamic>(
        '/posts/$postId/comments',
        data: {'content': content, if (parentId != null) 'parent_id': parentId},
      ),
    ),
  );

  Future<void> deleteComment(String commentId) =>
      _call(() => _dio.delete<dynamic>('/posts/comments/$commentId'));

  /// Sparks a post, or takes the Spark back. [on] says which way.
  Future<SparkResult> sparkPost(String postId, {required bool on}) async =>
      SparkResult.fromJson(
        await _map(
          () => on
              ? _dio.post<dynamic>('/posts/$postId/spark')
              : _dio.delete<dynamic>('/posts/$postId/spark'),
        ),
      );

  Future<SparkResult> sparkComment(
    String commentId, {
    required bool on,
  }) async => SparkResult.fromJson(
    await _map(
      () => on
          ? _dio.post<dynamic>('/posts/comments/$commentId/spark')
          : _dio.delete<dynamic>('/posts/comments/$commentId/spark'),
    ),
  );

  static const _unexpected = ApiException(
    'The server sent an unexpected response.',
  );

  Future<Map<String, dynamic>> _map(
    Future<Response<dynamic>> Function() request,
  ) async {
    final data = await _call(request);
    if (data is! Map<String, dynamic>) throw _unexpected;
    return data;
  }

  Future<Object?> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
