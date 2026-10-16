import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/firebase_options.dart';
import 'package:serafim/src/core/errors/human_error.dart';

import 'package:serafim/src/data/services/push_service.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/user_card.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(apiDioProvider));
});

/// How push registration on this phone is going, in words for the settings
/// screen. [ok] is true only once the server has this phone's token.
class PushStatus {
  const PushStatus(this.message, {this.ok = false});

  final String message;
  final bool ok;

  static const unknown = PushStatus('Not started yet.');
}

class PushStatusNotifier extends Notifier<PushStatus> {
  @override
  PushStatus build() => PushStatus.unknown;

  void set(PushStatus status) => state = status;
}

final pushStatusProvider = NotifierProvider<PushStatusNotifier, PushStatus>(
  PushStatusNotifier.new,
);

/// Message ids a banner has already been shown for, so a message that arrives
/// both over the socket and as a push is announced once.
final shownAlertIdsProvider = Provider<Set<String>>((ref) => <String>{});

/// Everything Firebase Cloud Messaging on this phone: permission, the device
/// token and keeping the backend's copy of it current, showing a banner for a
/// push that arrives while the app is open, and opening the right chat when a
/// notification is tapped.
///
/// Push is only for Android and iOS; on desktop/web every method is a no-op.
class PushRegistrar {
  PushRegistrar(this._ref);

  final Ref _ref;

  bool _firebaseReady = false;
  bool _started = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[push] $message');
    }
  }

  void _status(String message, {bool ok = false}) {
    _log(message);
    _ref.read(pushStatusProvider.notifier).set(PushStatus(message, ok: ok));
  }

  Future<bool> _ensureFirebase() async {
    if (!_supported) {
      _status('Push notifications are not available on this device.');
      return false;
    }
    if (_firebaseReady) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseReady = true;
    } catch (error) {
      // Unsupported platform or broken config: the app works, minus push.
      _status(
        "Push notifications couldn't start on this device. ${humanError(error)}",
      );
    }
    return _firebaseReady;
  }

  /// Asks permission, registers this phone with the backend, and starts
  /// listening. Calling it again (e.g. after the preview setting changes)
  /// just re-registers.
  Future<void> start({required bool showPreview}) async {
    if (!await _ensureFirebase()) return;
    final messaging = FirebaseMessaging.instance;

    try {
      // Android 13+ and iOS show the system prompt; elsewhere this is a no-op.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _status(
          'Notifications are blocked for Serafim. Turn them on in your '
          "phone's settings (App info → Notifications).",
        );
      }

      final token = await messaging.getToken();
      if (token == null) {
        _status(
          'Google did not give this phone a notification token. Check that '
          'Google Play services is installed and up to date.',
        );
      } else {
        final registered = await _register(token, showPreview);
        if (registered &&
            settings.authorizationStatus != AuthorizationStatus.denied) {
          _status(
            'Registered with the server. This phone can receive pushes.',
            ok: true,
          );
        }
      }
    } catch (error) {
      _status("Couldn't set up push notifications. ${humanError(error)}");
    }

    if (_started) return;
    _started = true;

    _subscriptions
      ..add(
        messaging.onTokenRefresh.listen((token) {
          final preview = _ref.read(settingsProvider).pushPreviews;
          _register(token, preview);
        }),
      )
      ..add(FirebaseMessaging.onMessage.listen(_onForegroundMessage))
      ..add(FirebaseMessaging.onMessageOpenedApp.listen(_openChatFrom));

    // The app was launched by tapping a notification.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _openChatFrom(initial);
  }

  /// Stops listening (e.g. on sign-out) without touching the backend.
  void stopListening() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _started = false;
  }

  /// Returns whether the server now has this token.
  Future<bool> _register(String token, bool showPreview) async {
    try {
      await _ref
          .read(pushServiceProvider)
          .registerDevice(
            token: token,
            platform: Platform.isIOS ? 'ios' : 'android',
            showPreview: showPreview,
          );
      return true;
    } catch (error) {
      _status(
        "The server didn't accept this phone for notifications. ${humanError(error)}",
      );
      return false;
    }
  }

  /// Stops pushes to this phone: tells the backend, then discards the token so
  /// it can never be reused by whoever signs in next. Safe to call anytime.
  Future<void> unregisterThisDevice() async {
    stopListening();
    if (!_supported || !_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _ref.read(pushServiceProvider).unregisterDevice(token);
      }
    } catch (error) {
      _log('could not unregister on the backend: $error');
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  // A push that arrives while the app is on screen: the OS shows nothing, so
  // show the same in-app banner as a socket message.
  void _onForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final senderId = data['sender_id'] as String?;
    final messageId = data['message_id'] as String?;
    final me = _ref.read(currentAccountIdProvider);
    if (senderId == null || me == null) return;

    if (!_ref.read(settingsProvider).inAppAlerts) return;
    final shown = _ref.read(shownAlertIdsProvider);
    if (messageId != null && !shown.add(messageId)) return; // Already shown.
    if (shown.length > 100) shown.remove(shown.first);

    final roomId = ChatViewModel.buildRoomId(me, senderId);
    if (_ref.read(activeRoomProvider) == roomId) return;

    final notification = message.notification;
    _ref
        .read(inAppBannerProvider)
        .show(
          title: notification?.title ?? 'New message',
          body: notification?.body ?? '',
          onTap: () => _openChatFrom(message),
        );
    if (_ref.read(settingsProvider).alertSound) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _openChatFrom(RemoteMessage message) async {
    final senderId = message.data['sender_id'] as String?;
    if (senderId == null) return;

    final navigator = _ref.read(navigatorKeyProvider).currentState;
    if (navigator == null) return;

    try {
      final sender = await _ref.read(socialServiceProvider).user(senderId);
      final nav = _ref.read(navigatorKeyProvider).currentState;
      if (nav != null) openChatWithNavigator(nav, sender);
    } catch (error) {
      _log('could not open chat from notification: $error');
    }
  }
}

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  final registrar = PushRegistrar(ref);
  ref.onDispose(registrar.stopListening);
  return registrar;
});

/// Keeps push registration in step with sign-in and the notification
/// settings. Watched from the main screen, like the chat view model.
final pushLifecycleProvider = Provider<void>((ref) {
  final account = ref.watch(currentAccountIdProvider);
  final enabled = ref.watch(
    settingsProvider.select((s) => s.pushNotifications),
  );
  final preview = ref.watch(settingsProvider.select((s) => s.pushPreviews));
  final registrar = ref.read(pushRegistrarProvider);

  if (account == null) return;

  if (enabled) {
    unawaited(registrar.start(showPreview: preview));
  } else {
    unawaited(registrar.unregisterThisDevice());
  }
});
