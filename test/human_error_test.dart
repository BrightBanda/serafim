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
        contains('sign in again'),
      );
      expect(
        viaApi(400, {'detail': 'Username already taken.'}),
        contains('username is already taken'),
      );
      expect(
        viaApi(409, {'detail': "Username 'sam' already exists."}),
        'That username is already taken. Try another one.',
      );
      expect(
        viaApi(409, {'error_code': 'username_taken'}),
        'That username is already taken. Try another one.',
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
      expect(m, contains("Try signing out and back in"));
      expect(
        viaApi(404, {'message': 'Bucket not found'}),
        contains("can't be added right now"),
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
          contains("isn't available right now"),
        );
        expect(
          viaApi(500, 'Traceback (most recent call last): boom'),
          contains('Something went wrong'),
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
      expect(offline.message, contains('Check your internet'));
      final slow = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(slow.message, contains('try again'));
    });
  });

  test('no message talks about servers, sessions or waking up', () {
    final messages = [
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
      ])
        viaApi(status, null),
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.badCertificate,
      ])
        ApiException.fromDio(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: type,
          ),
        ).message,
      humanError(const SocketException('x')),
      humanError(const FormatException('x')),
    ];
    for (final m in messages) {
      expect(m.toLowerCase(), isNot(contains('server')), reason: m);
      expect(m.toLowerCase(), isNot(contains('session')), reason: m);
      expect(m.toLowerCase(), isNot(contains('waking')), reason: m);
    }
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
        contains('Check your internet'),
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
      expect(humanError(const FileSystemException('x')), contains('out of space'));
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
