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

  /// Dio authenticated as the signed-in user, with `apikey` set.
  final Dio _dio;
  final String _supabaseUrl;

  /// Returns the public URL of the uploaded picture.
  Future<String> uploadAvatar(String userId, Uint8List jpegBytes) =>
      _upload('$userId/avatar.jpg', jpegBytes);

  /// A group's photo. Stored in the uploader's own folder (all the bucket
  /// policies allow), under a name per group.
  Future<String> uploadGroupPhoto(
    String userId,
    String groupId,
    Uint8List jpegBytes,
  ) => _upload('$userId/group_$groupId.jpg', jpegBytes);

  Future<String> _upload(String path, Uint8List jpegBytes) async {
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
