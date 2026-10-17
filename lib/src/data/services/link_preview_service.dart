import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/link_preview.dart';

/// Asks the backend for a link's preview. The page itself is never loaded by
/// the app: the server fetches it (safely) and returns text and a thumbnail.
class LinkPreviewService {
  const LinkPreviewService(this._dio);

  final Dio _dio;

  /// Null when the server has nothing to show for [url].
  Future<LinkPreview?> fetch(String url) async {
    try {
      final response = await _dio.get<dynamic>(
        '/link-preview',
        queryParameters: {'url': url},
        options: Options(
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
        ),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      return LinkPreview.fromJson(data);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 400 || status == 404) return null;
      throw ApiException.fromDio(error);
    }
  }
}
