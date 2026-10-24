import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/core/platform/google_support.dart';
import 'package:serafim/src/data/services/backup_service.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How often an automatic backup is made.
enum BackupFrequency {
  weekly('Weekly', 'Once a week'),
  monthly('Monthly', 'Once a month');

  const BackupFrequency(this.label, this.description);

  final String label;
  final String description;

  static BackupFrequency parse(String? name) => BackupFrequency.values
      .firstWhere((f) => f.name == name, orElse: () => BackupFrequency.weekly);

  /// When the backup after one made at [last] is due: seven days later, or
  /// the same day next month (the last day, when next month is shorter).
  DateTime nextAfter(DateTime last) {
    switch (this) {
      case BackupFrequency.weekly:
        return last.add(const Duration(days: 7));
      case BackupFrequency.monthly:
        final firstOfNext = DateTime(last.year, last.month + 1);
        final daysInNext = DateTime(
          firstOfNext.year,
          firstOfNext.month + 1,
          0,
        ).day;
        return DateTime(
          firstOfNext.year,
          firstOfNext.month,
          last.day > daysInNext ? daysInNext : last.day,
          last.hour,
          last.minute,
        );
    }
  }
}

/// Automatic Google Drive backups: the setting, and how the last one went.
class AutoBackupState {
  const AutoBackupState({
    this.enabled = false,
    this.frequency = BackupFrequency.weekly,
    this.lastSuccess,
    this.lastAttempt,
    this.lastError,
    this.running = false,
    this.lastRunAutomatic = false,
  });

  final bool enabled;
  final BackupFrequency frequency;

  /// When a Drive backup (automatic or by hand) last worked.
  final DateTime? lastSuccess;

  /// When one was last tried, whether or not it worked.
  final DateTime? lastAttempt;

  /// Why the last try failed; null when it worked.
  final String? lastError;

  /// A backup is on its way to Drive right now.
  final bool running;

  /// The last (or current) backup was started by the schedule, not a tap.
  final bool lastRunAutomatic;

  /// When the next automatic backup is due. Null when they are off, or when
  /// there has never been one (the first is due at once).
  DateTime? get nextDue {
    final last = lastSuccess;
    return !enabled || last == null ? null : frequency.nextAfter(last);
  }

  AutoBackupState copyWith({
    bool? enabled,
    BackupFrequency? frequency,
    DateTime? lastSuccess,
    DateTime? lastAttempt,
    String? Function()? lastError,
    bool? running,
    bool? lastRunAutomatic,
  }) {
    return AutoBackupState(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      lastSuccess: lastSuccess ?? this.lastSuccess,
      lastAttempt: lastAttempt ?? this.lastAttempt,
      lastError: lastError == null ? this.lastError : lastError(),
      running: running ?? this.running,
      lastRunAutomatic: lastRunAutomatic ?? this.lastRunAutomatic,
    );
  }
}

/// Makes a Google Drive backup when one is due.
///
/// Neither Android nor iOS lets an app reach the person's Google account
/// reliably while it is closed, so there is no job registered with the system.
/// Instead the schedule is checked whenever Serafim starts or comes back to
/// the screen (see [attach]): if the last backup is older than the chosen
/// frequency, a new one is made then, silently. If the app is not opened for
/// a while, the backup happens the next time it is. Because nothing is
/// registered with the system, changing the frequency or switching backups
/// off takes effect immediately, and nothing can run twice: one backup at a
/// time, whether started by the schedule or a tap.
class AutoBackupController extends Notifier<AutoBackupState> {
  static const _enabled = 'settings.autoBackup';
  static const _frequency = 'settings.autoBackupFrequency';
  static const _lastSuccess = 'backup.lastSuccess';
  static const _lastAttempt = 'backup.lastAttempt';
  static const _lastError = 'backup.lastError';

  /// After a failed automatic backup, wait this long before trying again, so
  /// a phone without a connection is not retried on every return to the app.
  static const retryAfter = Duration(hours: 6);

  /// Swappable in tests.
  DateTime Function() clock = DateTime.now;

  AppLifecycleListener? _lifecycle;
  Future<String?>? _inFlight;

  BackupService get _backup => ref.read(backupServiceProvider);

  @override
  AutoBackupState build() {
    ref.onDispose(() => _lifecycle?.dispose());
    final p = ref.watch(sharedPreferencesProvider);
    DateTime? time(String key) {
      final ms = p.getInt(key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return AutoBackupState(
      enabled: p.getBool(_enabled) ?? false,
      frequency: BackupFrequency.parse(p.getString(_frequency)),
      lastSuccess: time(_lastSuccess),
      lastAttempt: time(_lastAttempt),
      lastError: p.getString(_lastError),
    );
  }

  /// Starts checking the schedule: now, and each time the app returns to the
  /// screen. Safe to call more than once.
  void attach() {
    _lifecycle ??= AppLifecycleListener(onResume: runIfDue);
    runIfDue();
  }

  /// Whether the schedule wants a backup at [now].
  bool isDue(DateTime now) {
    final s = state;
    if (!s.enabled || s.running) return false;
    final failedAt = s.lastError == null ? null : s.lastAttempt;
    if (failedAt != null && now.isBefore(failedAt.add(retryAfter))) {
      return false;
    }
    final last = s.lastSuccess;
    return last == null || !now.isBefore(s.frequency.nextAfter(last));
  }

  /// Makes an automatic backup if one is due; otherwise does nothing.
  Future<void> runIfDue() async {
    if (!googleSignInSupported || !isDue(clock())) return;
    await _run(automatic: true);
  }

  /// Turns automatic backups on or off. Existing backups are never touched.
  ///
  /// Turning them on makes the first backup straight away when one is due,
  /// asking for Google Drive access if needed — that is what lets later
  /// backups happen without asking. If the person declines, automatic
  /// backups stay off. Returns a message to show, or null.
  Future<String?> setEnabled(bool on) async {
    _save(enabled: on);
    if (!on || !isDue(clock())) return null;
    try {
      return await _run(automatic: false, rethrowCancel: true);
    } on GoogleSignInCancelled {
      _save(enabled: false);
      return 'Automatic backup needs access to Google Drive.';
    }
  }

  void setFrequency(BackupFrequency frequency) {
    _save(frequency: frequency);
    // Weekly after monthly can make one due now.
    runIfDue();
  }

  /// A backup the person asked for. Works whether or not automatic backups
  /// are on, and resets their schedule (each backup replaces the last one).
  /// Returns a message to show on failure, or null.
  ///
  /// Throws [GoogleSignInCancelled] if they closed the account picker.
  Future<String?> backUpNow() => _run(automatic: false, rethrowCancel: true);

  /// One backup at a time: a second request while one runs gets the same
  /// result instead of starting another upload.
  Future<String?> _run({required bool automatic, bool rethrowCancel = false}) {
    return _inFlight ??= _upload(
      automatic: automatic,
      rethrowCancel: rethrowCancel,
    ).whenComplete(() => _inFlight = null);
  }

  Future<String?> _upload({
    required bool automatic,
    required bool rethrowCancel,
  }) async {
    final started = clock();
    state = state.copyWith(running: true, lastRunAutomatic: automatic);
    // Recorded first: if the app is closed half-way, nothing claims success,
    // so the backup is simply due again next time.
    _prefs.setInt(_lastAttempt, started.millisecondsSinceEpoch);
    try {
      await _backup.backUpToDrive(interactive: !automatic);
      _prefs.setInt(_lastSuccess, started.millisecondsSinceEpoch);
      _prefs.remove(_lastError);
      if (ref.mounted) {
        state = state.copyWith(
          running: false,
          lastSuccess: started,
          lastAttempt: started,
          lastError: () => null,
        );
      }
      return null;
    } on GoogleSignInCancelled {
      // Not a failure of the backup: they backed out of the account picker.
      if (ref.mounted) state = state.copyWith(running: false);
      if (rethrowCancel) rethrow;
      return null;
    } catch (error) {
      final message = humanError(
        error,
        fallback: 'The backup could not be made.',
      );
      _prefs.setString(_lastError, message);
      if (ref.mounted) {
        state = state.copyWith(
          running: false,
          lastAttempt: started,
          lastError: () => message,
        );
      }
      return message;
    }
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  void _save({bool? enabled, BackupFrequency? frequency}) {
    state = state.copyWith(enabled: enabled, frequency: frequency);
    if (enabled != null) _prefs.setBool(_enabled, enabled);
    if (frequency != null) _prefs.setString(_frequency, frequency.name);
  }
}

final autoBackupProvider =
    NotifierProvider<AutoBackupController, AutoBackupState>(
      AutoBackupController.new,
    );
