import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// Uploads profile pictures to the public `avatars` Supabase Storage bucket.
///
/// Only profile pictures live in cloud storage — chat images stay on-device.
/// Each user writes to their own `<user id>/avatar.jpg`; the bucket policies
/// (see supabase/storage_avatars.sql) enforce that.
class AvatarStorageService {
  const AvatarStorageService(this._dio, this._supabaseUrl);

  static const bucket = 'avatars';

  /// Pictures attached to posts (at most 2 MB each, set on the bucket).
  static const postBucket = 'post-images';

  /// Dio authenticated as the signed-in user, with `apikey` set.
  final Dio _dio;
  final String _supabaseUrl;

  /// Returns the public URL of the uploaded picture.
  Future<String> uploadAvatar(String userId, Uint8List jpegBytes) =>
      _upload(bucket, '$userId/avatar.jpg', jpegBytes);

  /// A group's photo. Stored in the uploader's own folder (all the bucket
  /// policies allow), under a name per group.
  Future<String> uploadGroupPhoto(
    String userId,
    String groupId,
    Uint8List jpegBytes,
  ) => _upload(bucket, '$userId/group_$groupId.jpg', jpegBytes);

  /// One picture on a post. Every picture gets its own name, so nothing is
  /// replaced and old links keep working.
  Future<String> uploadPostImage(String userId, Uint8List jpegBytes) {
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${jpegBytes.length}.jpg';
    return _upload(postBucket, '$userId/$name', jpegBytes);
  }

  Future<String> _upload(
    String bucket,
    String path,
    Uint8List jpegBytes,
  ) async {
    try {
      await _dio.post<dynamic>(
        '/object/$bucket/$path',
        data: Stream<List<int>>.value(jpegBytes),
        options: Options(
          contentType: 'image/jpeg',
          headers: {
            Headers.contentLengthHeader: jpegBytes.length,
            'x-upsert': 'true',
            'cache-control': 'max-age=3600',
          },
        ),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }

    final base = _supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    // The path never changes, so a version query busts image caches after a
    // replace.
    final version = DateTime.now().millisecondsSinceEpoch;
    return '$base/storage/v1/object/public/$bucket/$path?v=$version';
  }
}
