import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/core/network/api_exception.dart';

DioException serverError(int status, Object? body) {
  final options = RequestOptions(path: '/x');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: status, data: body),
    type: DioExceptionType.badResponse,
  );
}

String viaApi(int status, Object? body) =>
    ApiException.fromDio(serverError(status, body)).message;

void main() {
  group('server messages are rewritten for people', () {
    test('known sign-in codes get plain wording', () {
      expect(
        viaApi(400, {
          'error_code': 'invalid_credentials',
          'msg': 'Invalid login credentials',
        }),
        'That email or password is incorrect.',
      );
      expect(
        viaApi(422, {
          'error_code': 'user_already_exists',
          'msg': 'User already registered',
        }),
        contains('already exists'),
      );
      expect(
        viaApi(400, {
          'error_code': 'email_not_confirmed',
          'msg': 'Email not confirmed',
        }),
        contains('confirm your email'),
      );
      expect(
        viaApi(429, {'error_code': 'over_request_rate_limit', 'msg': 'x'}),
        contains('wait a minute'),
      );
    });

    test('phrases without a code are caught too', () {
      expect(
        viaApi(400, {'msg': 'Invalid login credentials'}),
        'That email or password is incorrect.',
      );
      expect(
        viaApi(401, {'detail': 'Invalid or missing access token.'}),
        contains('session has expired'),
      );
      expect(
        viaApi(400, {'detail': 'Username already taken.'}),
        contains('username is already taken'),
      );
      expect(
        viaApi(400, {'msg': 'Unsupported provider: provider is not enabled'}),
        contains("Google sign-in isn't switched on"),
      );
      expect(
        viaApi(400, {'msg': 'Bad ID token nonce'}),
        contains("couldn't verify"),
      );
    });

    test('storage errors never expose database jargon', () {
      final m = viaApi(403, {
        'statusCode': '403',
        'error': 'Unauthorized',
        'message': 'new row violates row-level security policy',
      });
      expect(m.toLowerCase(), isNot(contains('row')));
      expect(m, contains("don't have permission"));
      expect(
        viaApi(404, {'message': 'Bucket not found'}),
        contains("isn't set up"),
      );
    });

    test(
      'framework prefixes are stripped and the text reads as a sentence',
      () {
        expect(
          viaApi(422, {
            'detail': [
              {
                'msg': 'Value error, username must be 3-30 characters',
                'type': 'value_error',
              },
            ],
          }),
          'Username must be 3-30 characters.',
        );
      },
    );

    test(
      'HTML pages, stack traces and walls of text fall back to the status',
      () {
        expect(
          viaApi(502, '<html><body>Bad gateway</body></html>'),
          contains('temporarily unavailable'),
        );
        expect(
          viaApi(500, 'Traceback (most recent call last): boom'),
          contains('server ran into a problem'),
        );
        expect(viaApi(400, 'x' * 500), isNot(contains('xxxx')));
      },
    );

    test('every common status has a human sentence', () {
      for (final status in [
        400,
        401,
        403,
        404,
        409,
        413,
        422,
        429,
        500,
        502,
        503,
        504,
        418,
      ]) {
        final m = viaApi(status, null);
        expect(m, isNotEmpty);
        expect(m, endsWith('.'));
      }
    });

    test('connection failures say what to do', () {
      final offline = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(offline.message, contains('internet connection'));
      final slow = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(slow.message, contains('try again'));
    });
  });

  group('humanError turns anything into plain language', () {
    final raw = <String, Object?>{
      'ApiException': const ApiException(
        'Your session has expired. Please sign in again.',
      ),
      'DioException': serverError(500, null),
      'SocketException': const SocketException('Failed host lookup: x'),
      'HandshakeException': const HandshakeException('bad cert'),
      'TimeoutException': TimeoutException('later'),
      'FormatException': const FormatException('Unexpected character'),
      'FileSystemException': const FileSystemException('disk full', '/data/x'),
      'PlatformException': PlatformException(
        code: 'weird',
        message: 'NSInternalInconsistency',
      ),
      'photo denied': PlatformException(code: 'photo_access_denied'),
      'camera denied': PlatformException(code: 'camera_access_denied'),
      'MissingPluginException': MissingPluginException('no impl'),
      'UnimplementedError': UnimplementedError(),
      'UnsupportedError': UnsupportedError('nope'),
      'StateError': StateError('Bad state: no element'),
      'TypeError-ish': ArgumentError('x'),
      'plain Exception': Exception('boom'),
      'String': 'java.lang.NullPointerException',
      'null': null,
    };

    test('nothing technical ever reaches the screen', () {
      const banned = [
        'Exception',
        'Error',
        'Instance of',
        'dart:',
        '#0',
        'null',
        'Failed host',
        'NSInternal',
        'java.',
        'Bad state',
      ];
      raw.forEach((name, error) {
        final message = humanError(error);
        for (final bad in banned) {
          expect(message, isNot(contains(bad)), reason: '$name -> "$message"');
        }
        expect(message, isNotEmpty, reason: name);
        expect(message, endsWith('.'), reason: '$name -> "$message"');
      });
    });

    test('the right advice for the right problem', () {
      expect(
        humanError(const SocketException('x')),
        contains('internet connection'),
      );
      expect(humanError(TimeoutException('x')), contains('too long'));
      expect(
        humanError(PlatformException(code: 'photo_access_denied')),
        contains('photos'),
      );
      expect(
        humanError(PlatformException(code: 'camera_access_denied')),
        contains('camera'),
      );
      expect(humanError(const FileSystemException('x')), contains('storage'));
      expect(humanError(UnimplementedError()), contains("isn't available"));
    });

    test('an ApiException keeps its own friendly message', () {
      expect(
        humanError(const ApiException('That username is already taken.')),
        'That username is already taken.',
      );
    });

    test('a caller can supply a better fallback for unknown errors', () {
      expect(
        humanError(Exception('?'), fallback: "Couldn't load your chats."),
        "Couldn't load your chats.",
      );
      // ...but known errors still use their specific message.
      expect(
        humanError(const SocketException('x'), fallback: 'ignored'),
        contains('internet'),
      );
    });
  });
}
