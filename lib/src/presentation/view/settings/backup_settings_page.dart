import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/core/platform/google_support.dart';
import 'package:serafim/src/data/services/backup_service.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Export and import the chat database, and back it up to Google Drive.
class BackupSettingsPage extends ConsumerStatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  ConsumerState<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends ConsumerState<BackupSettingsPage> {
  bool _busy = false;
  DriveBackup? _last;

  BackupService get _backup => ref.read(backupServiceProvider);

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
    final done = await _backup.backUpToDrive();
    if (mounted) setState(() => _last = done);
    _say('Backed up to Google Drive.');
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

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'BACKUP & RESTORE',
      children: [
        const SettingsSectionLabel('Save to a file'),
        SerafimButton(label: 'Export chats', onPressed: _busy ? null : _export),
        const SizedBox(height: 8),
        SerafimButton(
          label: 'Import from file',
          onPressed: _busy ? null : _import,
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
            onPressed: _busy ? null : _driveBackup,
          ),
          const SizedBox(height: 8),
          SerafimButton(
            label: 'Restore from Google Drive',
            onPressed: _busy ? null : _driveRestore,
          ),
          SettingsNote(
            _last == null
                ? 'Stored in a private folder only Serafim can see. Each '
                      'backup replaces the previous one.'
                : 'Last backup: ${_when(_last!.modified)}. Stored in a '
                      'private folder only Serafim can see.',
          ),
        ],
        if (_busy)
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
