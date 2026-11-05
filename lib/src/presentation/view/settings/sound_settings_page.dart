import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/core/platform/sound_board.dart';
import 'package:serafim/src/providers/sound_providers.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Settings → Notifications → Sounds: on or off, how loud, and what plays
/// for each event (a built-in sound, none, or one of your own).
class SoundSettingsPage extends ConsumerWidget {
  const SoundSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(soundSettingsProvider);
    final c = ref.read(soundSettingsProvider.notifier);
    return SettingsScaffold(
      title: 'SOUNDS',
      children: [
        SettingsSwitchRow(
          key: const ValueKey('sounds-enabled'),
          title: 'In-app sounds',
          subtitle: 'Play sounds while Serafim is open.',
          value: s.enabled,
          onChanged: c.setEnabled,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(Icons.volume_down, color: AppColors.textDim),
              Expanded(
                child: Slider(
                  key: const ValueKey('sounds-volume'),
                  value: s.volume,
                  activeColor: AppColors.primary,
                  onChanged: s.enabled ? c.setVolume : null,
                  onChangeEnd: (_) => ref
                      .read(soundBoardProvider)
                      .preview(s.choiceFor(SoundEvent.received)),
                ),
              ),
              Icon(Icons.volume_up, color: AppColors.textDim),
            ],
          ),
        ),
        const SettingsNote(
          "Sounds follow your phone's notification volume and silent mode, "
          'and never pause your music.',
        ),
        const SettingsSectionLabel('What plays'),
        for (final event in SoundEvent.values)
          _EventRow(
            event: event,
            choice: s.choiceFor(event),
            enabled: s.enabled,
          ),
      ],
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({
    required this.event,
    required this.choice,
    required this.enabled,
  });

  final SoundEvent event;
  final SoundChoice choice;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.paperAlt,
        shape: Border.all(color: AppColors.lineSoft, width: 1.5),
        child: ListTile(
          key: ValueKey('sound-${event.name}'),
          enabled: enabled,
          title: Text(event.label, style: AppTextStyles.fieldInput),
          subtitle: Text(event.when, style: AppTextStyles.smallDim),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                choice.label,
                style: AppTextStyles.smallDim.copyWith(
                  color: AppColors.primaryPale,
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
          onTap: () => _pick(context, ref),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final board = ref.read(soundBoardProvider);
    final controller = ref.read(soundSettingsProvider.notifier);
    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      isScrollControlled: true,
      builder: (sheet) {
        Widget option(SoundChoice c) => RadioListTile<SoundChoice>(
          key: ValueKey('sound-option-${c.encode()}'),
          value: c,
          activeColor: AppColors.primary,
          title: Text(c.label, style: AppTextStyles.fieldInput),
          secondary: c.isNone
              ? null
              : IconButton(
                  tooltip: 'Play',
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.primaryPale,
                  ),
                  onPressed: () => board.preview(c),
                ),
        );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheet).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: RadioGroup<SoundChoice>(
                groupValue: choice,
                onChanged: (c) => Navigator.of(sheet).pop(c),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        event.label.toUpperCase(),
                        style: AppTextStyles.eyebrow,
                      ),
                    ),
                    option(const SoundChoice.none()),
                    for (final b in BuiltInSound.all)
                      option(SoundChoice.builtIn(b.id)),
                    if (choice.isFile) option(choice),
                    ListTile(
                      key: const ValueKey('sound-import'),
                      leading: Icon(
                        Icons.library_music_outlined,
                        color: AppColors.primaryPale,
                      ),
                      title: Text(
                        'Choose from your phone…',
                        style: AppTextStyles.fieldInput,
                      ),
                      subtitle: Text(
                        'Up to 10 seconds, 2 MB',
                        style: AppTextStyles.smallDim,
                      ),
                      onTap: () => Navigator.of(sheet).pop('import'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    try {
      if (picked == 'import') {
        final problem = await controller.importSound(event);
        if (problem != null) {
          messenger.showSnackBar(SnackBar(content: Text(problem)));
        } else {
          final now = ref.read(soundSettingsProvider).choiceFor(event);
          await board.preview(now);
        }
      } else if (picked is SoundChoice) {
        await controller.setChoice(event, picked);
        await board.preview(picked);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }
}
