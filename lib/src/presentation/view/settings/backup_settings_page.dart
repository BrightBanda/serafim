import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/core/platform/google_support.dart';
import 'package:serafim/src/data/services/backup_service.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/providers/backup_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Export and import the chat database, and back it up to Google Drive — by
/// hand, or automatically every week or month.
class BackupSettingsPage extends ConsumerStatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  ConsumerState<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends ConsumerState<BackupSettingsPage> {
  bool _busy = false;

  BackupService get _backup => ref.read(backupServiceProvider);
  AutoBackupController get _auto => ref.read(autoBackupProvider.notifier);

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } on GoogleSignInCancelled {
      // The person closed the account picker; nothing to report.
    } catch (e) {
      _say(humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRestore(String source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Restore from $source?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          'Chats on this device are replaced by the backup. Anything newer '
          'than the backup is lost.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// The open screens are still showing the old data, so ask for a restart
  /// rather than leave them half-updated.
  Future<void> _restored() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Backup restored',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          'Close Serafim and open it again to see your chats.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Close app'),
          ),
        ],
      ),
    );
  }

  Future<void> _export() => _run(() async {
    if (await _backup.exportToFile()) _say('Backup saved.');
  });

  Future<void> _import() async {
    if (!await _confirmRestore('a file')) return;
    await _run(() async {
      if (await _backup.restoreFromFile()) await _restored();
    });
  }

  Future<void> _driveBackup() => _run(() async {
    final error = await _auto.backUpNow();
    _say(error ?? 'Backed up to Google Drive.');
  });

  Future<void> _setAutomatic(bool on) => _run(() async {
    final before = ref.read(autoBackupProvider).lastSuccess;
    final error = await _auto.setEnabled(on);
    if (error != null) {
      _say(error);
    } else if (ref.read(autoBackupProvider).lastSuccess != before) {
      _say('Backed up to Google Drive. The next one is automatic.');
    }
  });

  Future<void> _driveRestore() async {
    if (!await _confirmRestore('Google Drive')) return;
    await _run(() async {
      if (await _backup.restoreFromDrive()) {
        await _restored();
      } else {
        _say('No backup found in Google Drive.');
      }
    });
  }

  String _when(DateTime t) =>
      '${t.day}/${t.month}/${t.year} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// What the automatic backup has done, and will do next.
  String _autoStatus(AutoBackupState auto) {
    final last = auto.lastSuccess;
    final lines = <String>[
      if (auto.lastError != null)
        'Last try failed: ${auto.lastError}'
      else if (last != null)
        'Last backup: ${_when(last)}.',
      if (auto.enabled)
        auto.nextDue == null
            ? 'Next backup: the next time Serafim is open.'
            : 'Next backup: ${_when(auto.nextDue!)}, or the first time '
                  'Serafim is open after that.',
    ];
    return [
      ...lines,
      'Backups are made while Serafim is open: your phone does not let it '
          'reach Google Drive while it is closed, so a backup that comes due '
          'then is made the next time you open the app.',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final auto = ref.watch(autoBackupProvider);
    final busy = _busy || auto.running;
    return SettingsScaffold(
      title: 'BACKUP & RESTORE',
      children: [
        const SettingsSectionLabel('Save to a file'),
        // Exporting copies a snapshot, so it never waits for an automatic
        // backup; restoring replaces the database, so it does.
        SerafimButton(label: 'Export chats', onPressed: _busy ? null : _export),
        const SizedBox(height: 8),
        SerafimButton(
          label: 'Import from file',
          onPressed: busy ? null : _import,
        ),
        const SettingsNote(
          'A copy of your chats saved outside the app. It survives updates '
          'and reinstalling, so export before installing a new version that '
          'is signed differently. Photos and voice notes stay on the phone '
          'and are not included.',
        ),
        if (googleSignInSupported) ...[
          const SettingsSectionLabel('Google Drive'),
          SerafimButton(
            label: 'Back up to Google Drive',
            onPressed: busy ? null : _driveBackup,
          ),
          const SizedBox(height: 8),
          SerafimButton(
            label: 'Restore from Google Drive',
            onPressed: busy ? null : _driveRestore,
          ),
          const SettingsNote(
            'Stored in a private folder only Serafim can see. Each backup '
            'replaces the previous one.',
          ),
          const SettingsSectionLabel('Automatic backup'),
          SettingsSwitchRow(
            title: 'Automatic backup',
            subtitle: 'Back up to Google Drive on a schedule',
            value: auto.enabled,
            onChanged: busy ? null : _setAutomatic,
          ),
          if (auto.enabled)
            for (final f in BackupFrequency.values)
              SettingsChoiceRow(
                title: f.label,
                subtitle: f.description,
                selected: auto.frequency == f,
                onTap: () => _auto.setFrequency(f),
              ),
          SettingsNote(_autoStatus(auto)),
        ],
        if (busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}
