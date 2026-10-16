import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/app_settings.dart';
import 'package:serafim/src/utils/in_app_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` with the loaded instance, so settings are readable
/// synchronously and the first frame already has the right text size.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

/// The root navigator. Lets non-widget code (the chat view model) open a chat
/// and show the message banner in the root overlay, above every page.
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => GlobalKey<NavigatorState>(),
);

/// The conversation currently on screen, so its messages don't raise alerts.
class ActiveRoomNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  // A chat page reports itself from a delayed callback, which can land after
  // the whole app state has been torn down (closing the app, switching
  // accounts). Touching a disposed notifier throws, so check first.
  void set(String? roomId) {
    if (ref.mounted) state = roomId;
  }

  /// Clears only if [roomId] is still the active one (a newer page may have
  /// already taken over).
  void clear(String roomId) {
    if (ref.mounted && state == roomId) state = null;
  }
}

final activeRoomProvider = NotifierProvider<ActiveRoomNotifier, String?>(
  ActiveRoomNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _readReceipts = 'settings.readReceipts';
  static const _alerts = 'settings.inAppAlerts';
  static const _sound = 'settings.alertSound';
  static const _quality = 'settings.imageQuality';
  static const _retention = 'settings.retentionDays';
  static const _textSize = 'settings.textSize';
  static const _theme = 'settings.themeChoice';
  static const _push = 'settings.pushNotifications';
  static const _pushPreview = 'settings.pushPreviews';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final p = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      sendReadReceipts: p.getBool(_readReceipts) ?? true,
      inAppAlerts: p.getBool(_alerts) ?? true,
      alertSound: p.getBool(_sound) ?? true,
      imageQuality: ImageQuality.parse(p.getString(_quality)),
      retentionDays: p.getInt(_retention) ?? 0,
      textSize: TextSize.parse(p.getString(_textSize)),
      themeChoice: ThemeChoice.parse(p.getString(_theme)),
      pushNotifications: p.getBool(_push) ?? true,
      pushPreviews: p.getBool(_pushPreview) ?? true,
    );
  }

  void setSendReadReceipts(bool value) {
    state = state.copyWith(sendReadReceipts: value);
    _prefs.setBool(_readReceipts, value);
  }

  void setInAppAlerts(bool value) {
    state = state.copyWith(inAppAlerts: value);
    _prefs.setBool(_alerts, value);
  }

  void setAlertSound(bool value) {
    state = state.copyWith(alertSound: value);
    _prefs.setBool(_sound, value);
  }

  void setImageQuality(ImageQuality value) {
    state = state.copyWith(imageQuality: value);
    _prefs.setString(_quality, value.name);
  }

  void setRetentionDays(int days) {
    state = state.copyWith(retentionDays: days);
    _prefs.setInt(_retention, days);
  }

  void setPushNotifications(bool value) {
    state = state.copyWith(pushNotifications: value);
    _prefs.setBool(_push, value);
  }

  void setPushPreviews(bool value) {
    state = state.copyWith(pushPreviews: value);
    _prefs.setBool(_pushPreview, value);
  }

  void setThemeChoice(ThemeChoice value) {
    state = state.copyWith(themeChoice: value);
    _prefs.setString(_theme, value.name);
  }

  void setTextSize(TextSize value) {
    state = state.copyWith(textSize: value);
    _prefs.setString(_textSize, value.name);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Top-of-screen message banners (see [InAppBannerService]).
final inAppBannerProvider = Provider<InAppBannerService>(
  (ref) => InAppBannerService(ref.watch(navigatorKeyProvider)),
);

/// The on-device copy of your profile, friends and the people you chat with.
final localCacheProvider = Provider<LocalCache>(
  (ref) => LocalCache(ref.watch(sharedPreferencesProvider)),
);

/// Riverpod's built-in behaviour is to silently retry a provider that throws —
/// up to 10 times, with growing delays — while reporting it as "loading". For
/// this app that meant a failed request (an unreachable server, a deleted
/// account) showed a spinner for minutes instead of the error and Retry button
/// every screen already has. So automatic retries are off: a failure is shown
/// at once, and the person decides whether to try again.
Duration? noAutoRetry(int retryCount, Object error) => null;
