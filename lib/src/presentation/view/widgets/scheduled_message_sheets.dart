import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/services/scheduled_message_service.dart';
import 'package:serafim/src/providers/scheduled_message_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// The quick choices for when a message should arrive, from [now]: in an hour,
/// this evening (while that is still ahead), tomorrow morning.
List<({String label, DateTime at})> quickTimes(DateTime now) {
  final evening = DateTime(now.year, now.month, now.day, 20);
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 8);
  return [
    (label: 'In 1 hour', at: now.add(const Duration(hours: 1))),
    if (evening.isAfter(now.add(const Duration(minutes: 5))))
      (label: 'Tonight, 8 PM', at: evening),
    (label: 'Tomorrow, 8 AM', at: tomorrow),
  ];
}

/// [when] in words: "Today, 8:00 PM", "Tomorrow, 8:00 AM" or a date.
String formatArrival(BuildContext context, DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final today = now ?? DateTime.now();
  final words = MaterialLocalizations.of(context);
  final time = words.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
  return switch (days) {
    0 => 'Today, $time',
    1 => 'Tomorrow, $time',
    _ => '${words.formatMediumDate(local)}, $time',
  };
}

/// Write a message and choose when it arrives. With [editing] it changes that
/// one instead.
Future<void> showScheduleComposer(
  BuildContext context, {
  String? recipientId,
  String? groupId,
  String initialText = '',
  ScheduledMessage? editing,
  VoidCallback? onScheduled,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.paper,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
  builder: (_) => _ScheduleComposer(
    recipientId: recipientId,
    groupId: groupId,
    initialText: initialText,
    editing: editing,
    onScheduled: onScheduled,
  ),
);

class _ScheduleComposer extends ConsumerStatefulWidget {
  const _ScheduleComposer({
    this.recipientId,
    this.groupId,
    this.initialText = '',
    this.editing,
    this.onScheduled,
  });

  final String? recipientId;
  final String? groupId;
  final String initialText;
  final ScheduledMessage? editing;
  final VoidCallback? onScheduled;

  @override
  ConsumerState<_ScheduleComposer> createState() => _ScheduleComposerState();
}

class _ScheduleComposerState extends ConsumerState<_ScheduleComposer> {
  late final _text = TextEditingController(
    text: widget.editing?.content ?? widget.initialText,
  );
  late DateTime? _when = widget.editing?.sendAt.toLocal();
  String? _textError;
  String? _timeError;
  String? _serverError;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDateAndTime() async {
    final now = DateTime.now();
    final start = _when ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: start.isBefore(now) ? now : start,
      firstDate: now,
      lastDate: now.add(const Duration(days: 364)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null || !mounted) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _timeError = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _text.text.trim();
    final when = _when;
    setState(() {
      _textError = text.isEmpty ? 'Write your message first.' : null;
      _timeError = when == null
          ? 'Choose when it should arrive.'
          : !when.isAfter(DateTime.now())
          ? 'Pick a time in the future.'
          : null;
      _serverError = null;
    });
    if (_textError != null || _timeError != null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final words = formatArrival(context, when!);
    final scheduled = ref.read(scheduledMessagesProvider.notifier);
    try {
      if (widget.editing case final old?) {
        await scheduled.change(old.id, content: text, sendAt: when);
      } else {
        await scheduled.schedule(
          recipientId: widget.recipientId,
          groupId: widget.groupId,
          content: text,
          sendAt: when,
        );
      }
      if (!mounted) return;
      widget.onScheduled?.call();
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('Will arrive: $words.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _serverError = humanError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final when = _when;
    final quick = quickTimes(DateTime.now());
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.editing == null ? 'SCHEDULE A MESSAGE' : 'CHANGE MESSAGE',
              style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'It goes out at the time you choose, even if your phone is off.',
              style: AppTextStyles.smallDim,
            ),
            const SizedBox(height: 14),
            UiTextField(
              key: const ValueKey('schedule-text'),
              label: 'YOUR MESSAGE',
              controller: _text,
              hintText: 'Happy birthday!',
              minLines: 2,
              maxLines: 4,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              errorText: _textError,
              onChanged: (_) {
                if (_textError != null) setState(() => _textError = null);
              },
            ),
            const SizedBox(height: 12),
            Text('WHEN IT ARRIVES', style: AppTextStyles.fieldLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in quick)
                  _TimeChip(
                    label: q.label,
                    selected: when == q.at,
                    onTap: () => setState(() {
                      _when = q.at;
                      _timeError = null;
                    }),
                  ),
                _TimeChip(
                  key: const ValueKey('schedule-pick'),
                  label: 'Pick date & time',
                  icon: Icons.calendar_month_outlined,
                  selected: false,
                  onTap: _pickDateAndTime,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              when == null
                  ? 'No time chosen yet.'
                  : 'Arrives: ${formatArrival(context, when)}',
              key: const ValueKey('schedule-arrives'),
              style: AppTextStyles.body.copyWith(
                fontSize: 12,
                color: when == null ? AppColors.textDim : AppColors.primaryPale,
              ),
            ),
            if ((_timeError ?? _serverError) case final error?) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: Colors.red.shade400)),
            ],
            const SizedBox(height: 16),
            SerafimButton(
              key: const ValueKey('schedule-submit'),
              label: _busy
                  ? 'SAVING…'
                  : widget.editing == null
                  ? 'SCHEDULE'
                  : 'SAVE',
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.paperRaised : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.lineSoft,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.textDim),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: AppTextStyles.smallDim.copyWith(
                color: selected ? AppColors.primaryPale : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Above the message box when this chat has scheduled messages. Shows nothing
/// otherwise.
class ScheduledMessagesBar extends ConsumerWidget {
  const ScheduledMessagesBar({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(scheduledInRoomProvider(roomId));
    if (items.isEmpty) return const SizedBox.shrink();
    final failed = items.where((m) => m.status == ScheduledStatus.failed);
    final waiting = items.length - failed.length;
    final text = failed.isNotEmpty
        ? "${failed.length} scheduled message${failed.length == 1 ? '' : 's'} "
              "couldn't be sent"
        : '$waiting scheduled message${waiting == 1 ? '' : 's'}';
    return GestureDetector(
      key: const ValueKey('scheduled-bar'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showSettledSheet<void>(
        context: context,
        backgroundColor: AppColors.paper,
        shape: const RoundedRectangleBorder(),
        isScrollControlled: true,
        builder: (_) => _ScheduledList(roomId: roomId),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.paperRaised,
          border: Border(top: BorderSide(color: AppColors.line, width: 2)),
        ),
        child: Row(
          children: [
            Icon(
              failed.isNotEmpty ? Icons.error_outline : Icons.schedule,
              size: 16,
              color: failed.isNotEmpty
                  ? Colors.red.shade400
                  : AppColors.primaryPale,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.body.copyWith(fontSize: 11),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}

/// This chat's scheduled messages: change or cancel what is waiting, see why
/// something failed.
class _ScheduledList extends ConsumerWidget {
  const _ScheduledList({required this.roomId});

  final String roomId;

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ScheduledMessage m,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(scheduledMessagesProvider.notifier).remove(m.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(scheduledInRoomProvider(roomId));
    if (items.isEmpty) {
      // The last one went out or was cancelled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'SCHEDULED MESSAGES',
              style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 10),
            for (final m in items)
              Container(
                key: ValueKey('scheduled-${m.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  border: Border.all(
                    color: m.status == ScheduledStatus.failed
                        ? Colors.red.shade400
                        : AppColors.lineSoft,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.status == ScheduledStatus.failed
                          ? m.failureText
                          : 'Arrives: ${formatArrival(context, m.sendAt)}',
                      style: AppTextStyles.smallDim.copyWith(
                        color: m.status == ScheduledStatus.failed
                            ? Colors.red.shade400
                            : AppColors.primaryPale,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (m.status == ScheduledStatus.pending)
                          TextButton(
                            key: ValueKey('scheduled-edit-${m.id}'),
                            onPressed: () =>
                                showScheduleComposer(context, editing: m),
                            child: Text(
                              'Change',
                              style: AppTextStyles.linkText,
                            ),
                          ),
                        TextButton(
                          key: ValueKey('scheduled-remove-${m.id}'),
                          onPressed: () => _remove(context, ref, m),
                          child: Text(
                            m.status == ScheduledStatus.failed
                                ? 'Dismiss'
                                : 'Cancel',
                            style: AppTextStyles.linkText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
