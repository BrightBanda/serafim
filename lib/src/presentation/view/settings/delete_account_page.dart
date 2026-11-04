import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/settings/backup_settings_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// Deleting your account for good (Settings → Privacy → Delete account).
/// Says what goes, offers a backup first, and asks for the username to be
/// typed back before the button works.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Only the button depends on what is typed, so only it is rebuilt.
    _typed.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool _matches(String? username) {
    final typed = _typed.text.trim().replaceFirst('@', '').toLowerCase();
    if (typed.isEmpty) return false;
    return username == null || typed == username.toLowerCase();
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(authViewModelProvider.notifier)
        .deleteAccount(_typed.text.trim());
    if (error != null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
      return;
    }
    navigator.popUntil((r) => r.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('Your account was deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(profileViewModelProvider).value?.username;
    return SettingsScaffold(
      title: 'DELETE ACCOUNT',
      children: [
        Text(
          'Deleting your account removes your profile, messages, posts, '
          'comments and files, and takes you out of every group and Circle. '
          'Nobody can undo it.',
          style: AppTextStyles.body.copyWith(color: AppColors.text),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BackupSettingsPage()),
          ),
          child: Text(
            'Back up your chats first',
            style: AppTextStyles.linkText,
          ),
        ),
        const SizedBox(height: 12),
        UiTextField(
          key: const ValueKey('delete-account-confirm'),
          label: username == null
              ? 'TYPE ANYTHING TO CONFIRM'
              : 'TYPE YOUR USERNAME ($username) TO CONFIRM',
          controller: _typed,
          hintText: username ?? '',
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
          ),
        ],
        const SizedBox(height: 20),
        SerafimButton(
          key: const ValueKey('delete-account-go'),
          label: _busy ? 'DELETING…' : 'DELETE MY ACCOUNT',
          onPressed: _busy || !_matches(username) ? null : _delete,
        ),
      ],
    );
  }
}
