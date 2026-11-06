import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/utils/echo_icon.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/echo.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/providers/echo_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// Your Echo: send one, or see how the live one is doing (how many it
/// reached, how many answered, End). Shown from the profile menu's Echo
/// item. Hidden when Echos are off in Settings.
class EchoSendCard extends ConsumerWidget {
  const EchoSendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewModelProvider).value;
    if (profile?.echoVisibility == EchoVisibility.off) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(myEchoProvider).value;
    final live = status?.echo;
    final now = DateTime.now().toUtc();
    final showLive = live != null && live.minutesLeft(now) > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        key: const ValueKey('echo-send'),
        behavior: HitTestBehavior.opaque,
        onTap: showLive ? null : () => showEchoComposer(context, status),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(
              color: showLive ? AppColors.primary : AppColors.lineSoft,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              EchoIcon(size: 24, color: AppColors.primaryPale),
              const SizedBox(width: 10),
              Expanded(
                child: showLive
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR ECHO · ${live.minutesLeft(now)} MIN LEFT',
                            style: AppTextStyles.eyebrow.copyWith(fontSize: 9),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            live.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.fieldInput,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Reached ${live.reachedCount} · '
                            '${live.responseCount} answered',
                            style: AppTextStyles.smallDim,
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Up for a chat?',
                            style: AppTextStyles.fieldInput.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Send an Echo to people who share your interests',
                            style: AppTextStyles.smallDim,
                          ),
                        ],
                      ),
              ),
              if (showLive)
                TextButton(
                  key: const ValueKey('echo-end'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref.read(echoActionsProvider).close(live.id);
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(humanError(e))),
                      );
                    }
                  },
                  child: Text('End', style: AppTextStyles.linkText),
                )
              else
                Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Your live Echo in a sheet: how it is doing, and End.
Future<void> showMyEchoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (_) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: EchoSendCard(),
      ),
    ),
  );
}

/// The sheet for sending an Echo: a short message and who it may reach.
/// The limits are explained up front when one applies.
Future<void> showEchoComposer(BuildContext context, MyEchoStatus? status) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (_) => _EchoComposer(status: status),
  );
}

class _EchoComposer extends ConsumerStatefulWidget {
  const _EchoComposer({required this.status});

  final MyEchoStatus? status;

  @override
  ConsumerState<_EchoComposer> createState() => _EchoComposerState();
}

class _EchoComposerState extends ConsumerState<_EchoComposer> {
  final _text = TextEditingController();
  EchoAudience _audience = EchoAudience.everyone;
  bool _busy = false;
  String? _error;

  /// Send was tapped with nothing written.
  bool _missingText = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _limitNote {
    final s = widget.status;
    if (s == null) return null;
    if (s.dailyLimitReached) {
      return "That's ${s.perDay} Echos today. You can send another tomorrow.";
    }
    final next = s.nextAllowedAt;
    final now = DateTime.now().toUtc();
    if (next != null && next.isAfter(now)) {
      return 'You can send another Echo in '
          '${next.difference(now).inMinutes + 1} min.';
    }
    return null;
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (_busy) return;
    if (text.isEmpty) {
      setState(() => _missingText = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final echo = await ref
          .read(echoActionsProvider)
          .send(text: text, audience: _audience);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Your Echo reached ${echo.reachedCount} '
            '${echo.reachedCount == 1 ? 'person' : 'people'}.',
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
    final blocked = _limitNote;
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
              'SEND AN ECHO',
              style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Up to ${Echo.reach} people get it as a notification. Whoever '
              'is interested can start a chat with you for the next '
              '${Echo.minutes} minutes.',
              style: AppTextStyles.smallDim,
            ),
            const SizedBox(height: 14),
            UiTextField(
              key: const ValueKey('echo-text'),
              label: 'YOUR MESSAGE',
              controller: _text,
              hintText: 'Bored, anyone want to talk football?',
              maxLength: Echo.textMax,
              maxLines: 2,
              errorText: _missingText ? 'Write a short message first.' : null,
              onChanged: (_) {
                if (_missingText) setState(() => _missingText = false);
              },
            ),
            const SizedBox(height: 12),
            Text('WHO CAN GET IT', style: AppTextStyles.fieldLabel),
            const SizedBox(height: 8),
            for (final a in EchoAudience.values)
              _AudienceOption(
                audience: a,
                selected: _audience == a,
                onTap: () => setState(() => _audience = a),
              ),
            if ((_error ?? blocked) != null) ...[
              const SizedBox(height: 12),
              Text(
                (_error ?? blocked)!,
                style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
              ),
            ],
            const SizedBox(height: 16),
            SerafimButton(
              key: const ValueKey('echo-post'),
              label: _busy ? 'SENDING…' : 'SEND ECHO',
              onPressed: _busy || blocked != null ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceOption extends StatelessWidget {
  const _AudienceOption({
    required this.audience,
    required this.selected,
    required this.onTap,
  });

  final EchoAudience audience;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('echo-audience-${audience.name}'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? AppColors.paperRaised : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.lineSoft,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                audience.label.toUpperCase(),
                style: AppTextStyles.fieldLabel.copyWith(
                  color: selected ? AppColors.primaryPale : AppColors.textDim,
                ),
              ),
            ),
            Flexible(
              child: Text(
                audience.description,
                textAlign: TextAlign.end,
                style: AppTextStyles.smallDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
