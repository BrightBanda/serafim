import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/config/app_config.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/data/services/push_service.dart';
import 'package:serafim/src/presentation/view/settings/notification_settings_page.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records requests and answers with a canned response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Dio _dio(_FakeAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://x.supabase.co/auth/v1'))
      ..httpClientAdapter = adapter;

void main() {
  group('Google ID token → Supabase session', () {
    final session = {
      'access_token': 'at',
      'refresh_token': 'rt',
      'expires_in': 3600,
      'user': {'id': 'user-1', 'email': 'a@b.c'},
    };

    test('posts the id_token grant with provider google', () async {
      final adapter = _FakeAdapter((_) => _json(200, session));
      final result = await AuthService(
        _dio(adapter),
      ).signInWithGoogleIdToken('G.ID.TOKEN');

      final request = adapter.requests.single;
      expect(request.path, '/token');
      expect(request.queryParameters, {'grant_type': 'id_token'});
      expect(request.data, {'provider': 'google', 'id_token': 'G.ID.TOKEN'});
      expect(result.accessToken, 'at');
      expect(result.userId, 'user-1');
    });

    test('a rejected token surfaces the server message', () async {
      final adapter = _FakeAdapter(
        (_) => _json(400, {'msg': 'Provider (google) is not enabled'}),
      );
      expect(
        AuthService(_dio(adapter)).signInWithGoogleIdToken('t'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('not enabled'))
              .having((e) => e.statusCode, 'status', 400),
        ),
      );
    });
  });

  group('GoogleAuthService', () {
    test('without a web client id it explains what is missing', () {
      expect(
        GoogleAuthService(webClientId: '').signIn(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('GOOGLE_WEB_CLIENT_ID'),
          ),
        ),
      );
    });
  });

  group('AppConfig', () {
    test('google sign-in is only "configured" once a web client id exists', () {
      const base = AppConfig(
        supabaseUrl: 'https://x.supabase.co',
        supabasePublishableKey: 'k',
        apiBaseUrl: 'http://api',
      );
      expect(base.googleSignInConfigured, isFalse);
      const withId = AppConfig(
        supabaseUrl: 'https://x.supabase.co',
        supabasePublishableKey: 'k',
        apiBaseUrl: 'http://api',
        googleWebClientId: '123.apps.googleusercontent.com',
      );
      expect(withId.googleSignInConfigured, isTrue);
    });
  });

  group('PushService', () {
    test(
      'registers a device with its token, platform and preview choice',
      () async {
        final adapter = _FakeAdapter((_) => ResponseBody.fromString('', 204));
        await PushService(
          Dio(BaseOptions(baseUrl: 'http://api'))..httpClientAdapter = adapter,
        ).registerDevice(
          token: 'fcm-token',
          platform: 'android',
          showPreview: false,
        );

        final r = adapter.requests.single;
        expect(r.method, 'POST');
        expect(r.path, '/devices');
        expect(r.data, {
          'token': 'fcm-token',
          'platform': 'android',
          'show_preview': false,
        });
      },
    );

    test('unregisters by token', () async {
      final adapter = _FakeAdapter((_) => ResponseBody.fromString('', 204));
      await PushService(
        Dio(BaseOptions(baseUrl: 'http://api'))..httpClientAdapter = adapter,
      ).unregisterDevice('fcm-token');

      final r = adapter.requests.single;
      expect(r.method, 'DELETE');
      expect(r.path, '/devices');
      expect(r.data, {'token': 'fcm-token'});
    });

    test('a failure becomes an ApiException', () {
      final adapter = _FakeAdapter(
        (_) => _json(401, {'detail': 'Invalid or missing access token.'}),
      );
      expect(
        PushService(
          Dio(BaseOptions(baseUrl: 'http://api'))..httpClientAdapter = adapter,
        ).registerDevice(token: 't' * 20, platform: 'ios', showPreview: true),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('push settings', () {
    Future<ProviderContainer> container([
      Map<String, Object> stored = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('both default to on and persist', () async {
      final c = await container();
      expect(c.read(settingsProvider).pushNotifications, isTrue);
      expect(c.read(settingsProvider).pushPreviews, isTrue);

      c.read(settingsProvider.notifier)
        ..setPushNotifications(false)
        ..setPushPreviews(false);

      final prefs = await SharedPreferences.getInstance();
      final again = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(again.dispose);
      expect(again.read(settingsProvider).pushNotifications, isFalse);
      expect(again.read(settingsProvider).pushPreviews, isFalse);
    });

    testWidgets('the settings page toggles push and gates the preview switch', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: NotificationSettingsPage()),
        ),
      );

      Switch switchFor(String title) => tester.widget<Switch>(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, title),
          matching: find.byType(Switch),
        ),
      );

      expect(find.text('Push notifications'), findsOneWidget);
      expect(switchFor('Show message previews').onChanged, isNotNull);

      await tester.tap(find.text('Push notifications'));
      await tester.pump();
      expect(c.read(settingsProvider).pushNotifications, isFalse);
      // Previews make no sense with push off, so that switch is disabled.
      expect(switchFor('Show message previews').onChanged, isNull);
    });
  });
}
