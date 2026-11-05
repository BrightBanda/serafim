import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/providers/nickname_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// Nicknames between you and one friend (chat ⋮ → Nicknames): what you call
/// them, which you can change, and what they call you.
class NicknamesPage extends ConsumerStatefulWidget {
  const NicknamesPage({
    super.key,
    required this.friendId,
    required this.friendName,
  });

  final String friendId;

  /// Their real name.
  final String friendName;

  @override
  ConsumerState<NicknamesPage> createState() => _NicknamesPageState();
}

class _NicknamesPageState extends ConsumerState<NicknamesPage> {
  late final _field = TextEditingController(
    text: ref.read(nicknameForProvider(widget.friendId)) ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save(String value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(nicknameServiceProvider)
          .set(widget.friendId, value.trim());
      ref.invalidate(nicknamesProvider);
      if (value.trim().isEmpty) _field.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            value.trim().isEmpty
                ? 'Nickname removed.'
                : '${widget.friendName} is now "${value.trim()}" to you.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theirs = ref.watch(nicknameFromProvider(widget.friendId));
    final mine = ref.watch(nicknameForProvider(widget.friendId));
    return SettingsScaffold(
      title: 'NICKNAMES',
      children: [
        SettingsSectionLabel('What you call ${widget.friendName}'),
        UiTextField(
          key: const ValueKey('nickname-field'),
          label: 'NICKNAME',
          controller: _field,
          hintText: widget.friendName,
          maxLength: 40,
        ),
        Text(
          'Only you see it in your chats. ${widget.friendName} can see what '
          'you call them.',
          style: AppTextStyles.smallDim,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
          ),
        ],
        const SizedBox(height: 14),
        SerafimButton(
          key: const ValueKey('nickname-save'),
          label: _busy ? 'SAVING…' : 'SAVE NICKNAME',
          onPressed: _busy ? null : () => _save(_field.text),
        ),
        if (mine != null) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              key: const ValueKey('nickname-remove'),
              onPressed: _busy ? null : () => _save(''),
              child: Text('Remove nickname', style: AppTextStyles.linkText),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SettingsSectionLabel('What ${widget.friendName} calls you'),
        Container(
          key: const ValueKey('nickname-theirs'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(
              color: theirs == null ? AppColors.lineSoft : AppColors.primary,
              width: 1.5,
            ),
          ),
          child: Text(
            theirs == null
                ? "${widget.friendName} hasn't given you a nickname yet."
                : '"$theirs"',
            style: theirs == null
                ? AppTextStyles.body
                : AppTextStyles.displayHeading.copyWith(fontSize: 20),
          ),
        ),
      ],
    );
  }
}
