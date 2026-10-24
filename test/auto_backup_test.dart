import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/services/backup_service.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/presentation/view/settings/backup_settings_page.dart';
import 'package:serafim/src/providers/backup_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Drive backup whose uploads the test can hold, fail or cancel.
class FakeBackup implements BackupService {
  final uploads = <bool>[]; // Whether each was allowed to ask the person.
  Completer<void>? gate;
  Object? failWith;

  @override
  Future<DriveBackup> backUpToDrive({bool interactive = true}) async {
    uploads.add(interactive);
    await gate?.future;
    final error = failWith;
    if (error != null) throw error;
    return DriveBackup(id: 'b', modified: DateTime(2026));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final monday = DateTime(2026, 10, 5, 9);

/// A fresh app start on the same phone storage.
ProviderContainer launch(SharedPreferences prefs, FakeBackup backup) {
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      backupServiceProvider.overrideWithValue(backup),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FakeBackup backup;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backup = FakeBackup();
  });

  AutoBackupController controller(ProviderContainer c, DateTime now) =>
      c.read(autoBackupProvider.notifier)..clock = () => now;

  group('BackupFrequency', () {
    test('weekly is seven days later', () {
      expect(
        BackupFrequency.weekly.nextAfter(monday),
        DateTime(2026, 10, 12, 9),
      );
    });

    test('monthly is the same day next month, or its last day', () {
      final m = BackupFrequency.monthly;
      expect(m.nextAfter(DateTime(2026, 1, 15, 8)), DateTime(2026, 2, 15, 8));
      expect(m.nextAfter(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      expect(m.nextAfter(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
      expect(m.nextAfter(DateTime(2026, 12, 20)), DateTime(2027, 1, 20));
    });
  });

  test('nothing happens while automatic backups are off', () async {
    final c = launch(prefs, backup);
    await controller(c, monday).runIfDue();
    expect(backup.uploads, isEmpty);
  });

  test('the setting and the schedule survive a restart', () async {
    var c = launch(prefs, backup);
    controller(c, monday);
    await c.read(autoBackupProvider.notifier).setEnabled(true);
    c.read(autoBackupProvider.notifier).setFrequency(BackupFrequency.monthly);
    expect(backup.uploads, [true]); // First one at once, may ask for access.

    c = launch(prefs, backup);
    final state = c.read(autoBackupProvider);
    expect(state.enabled, isTrue);
    expect(state.frequency, BackupFrequency.monthly);
    expect(state.lastSuccess, monday);
    expect(state.nextDue, DateTime(2026, 11, 5, 9));
  });

  test('a backup is made only once the chosen period has passed', () async {
    prefs.setBool('settings.autoBackup', true);
    prefs.setInt('backup.lastSuccess', monday.millisecondsSinceEpoch);

    var c = launch(prefs, backup);
    await controller(c, monday.add(const Duration(days: 6))).runIfDue();
    expect(backup.uploads, isEmpty);

    await controller(c, monday.add(const Duration(days: 7))).runIfDue();
    expect(backup.uploads, [false]); // Automatic: never asks the person.

    // Monthly: a week is not enough.
    prefs.setString('settings.autoBackupFrequency', 'monthly');
    prefs.setInt('backup.lastSuccess', monday.millisecondsSinceEpoch);
    c = launch(prefs, backup);
    await controller(c, monday.add(const Duration(days: 8))).runIfDue();
    expect(backup.uploads, [false]);
  });

  test('a schedule check and a tap at once make one upload', () async {
    prefs.setBool('settings.autoBackup', true);
    final c = launch(prefs, backup);
    final auto = controller(c, monday);
    backup.gate = Completer<void>();

    final scheduled = auto.runIfDue();
    final again = auto.runIfDue();
    final tapped = auto.backUpNow();
    expect(c.read(autoBackupProvider).running, isTrue);
    backup.gate!.complete();
    await Future.wait([scheduled, again, tapped]);

    expect(backup.uploads, hasLength(1));
    expect(c.read(autoBackupProvider).running, isFalse);
  });

  test(
    'a failure is recorded, then retried later, not on every resume',
    () async {
      prefs.setBool('settings.autoBackup', true);
      final c = launch(prefs, backup);
      backup.failWith = const DriveAccessNeeded();

      await controller(c, monday).runIfDue();
      final state = c.read(autoBackupProvider);
      expect(state.lastError, const DriveAccessNeeded().message);
      expect(state.lastSuccess, isNull);
      expect(prefs.getString('backup.lastError'), isNotNull);

      backup.failWith = null;
      await controller(c, monday.add(const Duration(hours: 1))).runIfDue();
      expect(backup.uploads, hasLength(1));

      await controller(c, monday.add(const Duration(hours: 7))).runIfDue();
      expect(backup.uploads, hasLength(2));
      expect(c.read(autoBackupProvider).lastError, isNull);
    },
  );

  test('declining Google Drive access leaves automatic backups off', () async {
    final c = launch(prefs, backup);
    backup.failWith = const GoogleSignInCancelled();
    final message = await controller(c, monday).setEnabled(true);

    expect(message, isNotNull);
    expect(c.read(autoBackupProvider).enabled, isFalse);
    expect(prefs.getBool('settings.autoBackup'), isFalse);
  });

  test('switching off stops the schedule', () async {
    prefs.setBool('settings.autoBackup', true);
    prefs.setInt('backup.lastSuccess', monday.millisecondsSinceEpoch);
    final c = launch(prefs, backup);
    await controller(c, monday).setEnabled(false);

    await controller(c, monday.add(const Duration(days: 60))).runIfDue();
    expect(backup.uploads, isEmpty);
    expect(launch(prefs, backup).read(autoBackupProvider).enabled, isFalse);
  });

  test('a backup by hand works with automatic backups off', () async {
    final c = launch(prefs, backup);
    expect(await controller(c, monday).backUpNow(), isNull);
    expect(backup.uploads, [true]);
    expect(c.read(autoBackupProvider).lastSuccess, monday);

    backup.failWith = const ApiException('Google Drive request failed.');
    expect(
      await c.read(autoBackupProvider.notifier).backUpNow(),
      'Google Drive request failed.',
    );
  });

  testWidgets('the schedule is checked at start and on every return', (
    t,
  ) async {
    prefs.setBool('settings.autoBackup', true);
    final c = launch(prefs, backup);
    final auto = controller(c, monday);

    auto.attach();
    await t.pump();
    expect(backup.uploads, hasLength(1));

    // A week later the app comes back to the screen.
    auto.clock = () => monday.add(const Duration(days: 7));
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump();
    expect(backup.uploads, hasLength(2));
  });

  group('backup settings screen', () {
    Future<void> showPage(WidgetTester t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: launch(prefs, backup),
          child: const MaterialApp(home: BackupSettingsPage()),
        ),
      );
      await t.pumpAndSettle();
    }

    bool selected(WidgetTester t, String title) => t
        .widget<SettingsChoiceRow>(
          find.widgetWithText(SettingsChoiceRow, title),
        )
        .selected;

    testWidgets('reopening shows the saved setting', (t) async {
      prefs.setBool('settings.autoBackup', true);
      prefs.setString('settings.autoBackupFrequency', 'monthly');
      prefs.setInt('backup.lastSuccess', monday.millisecondsSinceEpoch);
      await showPage(t);

      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(selected(t, 'Monthly'), isTrue);
      expect(selected(t, 'Weekly'), isFalse);
      expect(
        find.textContaining('Last backup: 5/10/2026 09:00'),
        findsOneWidget,
      );
    });

    testWidgets('the switch turns them on with a first backup, and the '
        'frequency can then be chosen', (t) async {
      await showPage(t);
      expect(find.byType(SettingsChoiceRow), findsNothing);

      await t.tap(find.byType(SwitchListTile));
      await t.pumpAndSettle();
      expect(backup.uploads, [true]);
      expect(prefs.getBool('settings.autoBackup'), isTrue);
      expect(
        find.text('Backed up to Google Drive. The next one is automatic.'),
        findsOneWidget,
      );

      await t.tap(find.text('Monthly'));
      await t.pumpAndSettle();
      expect(selected(t, 'Monthly'), isTrue);
      expect(prefs.getString('settings.autoBackupFrequency'), 'monthly');

      await t.tap(find.byType(SwitchListTile));
      await t.pumpAndSettle();
      expect(prefs.getBool('settings.autoBackup'), isFalse);
      expect(find.byType(SettingsChoiceRow), findsNothing);
    });
  });
}
