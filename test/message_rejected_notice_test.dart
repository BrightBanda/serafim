import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';

void main() {
  group('rejectionNotice', () {
    test('a suspended recipient uses the server text', () {
      expect(
        rejectionNotice({
          'type': 'message_rejected',
          'temp_id': 't1',
          'reason': 'user_unavailable',
          'message': 'User not available',
        }),
        'User not available',
      );
    });

    test('falls back to "User not available" without a server message', () {
      expect(
        rejectionNotice({'reason': 'user_unavailable'}),
        'User not available',
      );
      expect(
        rejectionNotice({'reason': 'user_unavailable', 'message': '  '}),
        'User not available',
      );
      expect(
        rejectionNotice({'reason': 'user_unavailable', 'message': 42}),
        'User not available',
      );
    });

    test('other reasons keep the silent failed status', () {
      for (final reason in [
        'attachments_require_friendship',
        'unknown_recipient',
        'not_a_member',
        null,
      ]) {
        expect(rejectionNotice({'reason': reason, 'message': 'x'}), isNull);
      }
    });
  });
}
