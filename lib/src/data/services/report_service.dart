import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// What can be reported.
enum ReportTarget { post, message }

/// Why something is reported (backend `app/api/reports.py`).
enum ReportReason {
  spam('Spam'),
  harassment('Harassment or bullying'),
  hate('Hate speech'),
  sexual('Sexual content'),
  violence('Violence or threats'),
  scam('Scam or fraud'),
  other('Something else');

  const ReportReason(this.label);

  final String label;
}

/// Sends reports to the SERAFIM admins (`POST /reports`).
class ReportService {
  const ReportService(this._dio);

  final Dio _dio;

  Future<void> report({
    required ReportTarget target,
    required String id,
    required ReportReason reason,
    String? note,
  }) async {
    try {
      await _dio.post<dynamic>(
        '/reports',
        data: {
          'target_type': target.name,
          'target_id': id,
          'reason': reason.name,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
