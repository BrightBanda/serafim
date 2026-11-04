import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/presentation/view/circle_invite_page.dart';
import 'package:serafim/src/presentation/view/widgets/circle_choices.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// A Circle's settings: its details (the Owner edits them), inviting
/// people, your notifications, and leaving or deleting it.
///
/// Pops with `true` when you are no longer in the Circle (you left it, or
/// deleted it), so the Circle's page closes as well.
class CircleSettingsPage extends ConsumerWidget {
  const CircleSettingsPage({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'CIRCLE SETTINGS',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: detail.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                humanError(e),
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (circle) => ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
            children: [
              if (circle.myRole?.isOwner == true) ...[
                const SettingsSectionLabel('Details'),
                _DetailsForm(circle: circle),
                const SizedBox(height: 24),
              ] else ...[
                const SettingsSectionLabel('Details'),
                Text(
                  "Only the Circle's owner can change its name, description "
                  'and rules.',
                  style: AppTextStyles.smallDim,
                ),
                const SizedBox(height: 24),
              ],
              if (circle.canInvite) ...[
                const SettingsSectionLabel('People'),
                _InviteRow(circle: circle),
                const SizedBox(height: 24),
              ],
              if (circle.isMember) ...[
                const SettingsSectionLabel('Notifications'),
                _NotificationSettings(circle: circle),
                const SizedBox(height: 24),
                _LeaveRow(circle: circle),
              ],
              if (circle.myRole?.isOwner == true) ...[
                const SizedBox(height: 12),
                _DangerRow(circle: circle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Owner's form: name, description, category, who can join, rules and
/// whether members can post. Saves only what changed.
class _DetailsForm extends ConsumerStatefulWidget {
  const _DetailsForm({required this.circle});

  final CircleDetail circle;

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  late final _name = TextEditingController(text: widget.circle.name);
  late final _description = TextEditingController(
    text: widget.circle.summary.description ?? '',
  );
  late final _rules = TextEditingController(text: widget.circle.rules ?? '');
  late String? _category = widget.circle.summary.category;
  late CircleVisibility _visibility = widget.circle.summary.visibility;
  late bool _posting = widget.circle.postingEnabled;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final c = widget.circle;
    final name = _name.text.trim();
    final description = _description.text.trim();
    final rules = _rules.text.trim();
    String? changed(String now, String? before) =>
        now == (before ?? '').trim() ? null : now;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(circleServiceProvider)
          .update(
            c.id,
            name: changed(name, c.name),
            description: changed(description, c.summary.description),
            // "" clears the category on the server.
            category: _category == c.summary.category ? null : _category ?? '',
            visibility: _visibility == c.summary.visibility
                ? null
                : _visibility,
            rules: changed(rules, c.rules),
            postingEnabled: _posting == c.postingEnabled ? null : _posting,
          );
      ref.invalidate(circleDetailProvider(c.id));
      ref.invalidate(myCirclesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Circle saved.')));
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiTextField(
          key: const ValueKey('circle-edit-name'),
          label: 'NAME',
          controller: _name,
          maxLength: CircleLimits.nameMax,
        ),
        const SizedBox(height: 12),
        UiTextField(
          key: const ValueKey('circle-edit-description'),
          label: 'WHAT IS IT ABOUT',
          controller: _description,
          hintText: 'A short line about who this is for.',
          maxLines: 4,
          minLines: 2,
          maxLength: CircleLimits.descriptionMax,
        ),
        const SizedBox(height: 16),
        Text('CATEGORY', style: AppTextStyles.fieldLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final category in circleCategories)
              CircleChoiceChip(
                label: category,
                selected: _category == category,
                onTap: () => setState(
                  () => _category = _category == category ? null : category,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('WHO CAN JOIN', style: AppTextStyles.fieldLabel),
        const SizedBox(height: 8),
        for (final visibility in CircleVisibility.values)
          CircleVisibilityOption(
            visibility: visibility,
            selected: _visibility == visibility,
            onTap: () => setState(() => _visibility = visibility),
          ),
        const SizedBox(height: 20),
        UiTextField(
          label: 'RULES',
          controller: _rules,
          hintText: 'What is expected of the people here.',
          maxLines: 6,
          minLines: 2,
          maxLength: CircleLimits.rulesMax,
        ),
        const SizedBox(height: 8),
        SettingsSwitchRow(
          title: 'Members can post',
          subtitle: 'Off makes the Circle read only for members',
          value: _posting,
          onChanged: (on) => setState(() => _posting = on),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
          ),
        ],
        const SizedBox(height: 16),
        SerafimButton(
          key: const ValueKey('circle-edit-save'),
          label: _busy ? 'SAVING…' : 'SAVE CHANGES',
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

/// Opens the page for inviting (or adding) friends.
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context) {
    final manager = circle.myRole?.canManage == true;
    return GestureDetector(
      key: const ValueKey('circle-invite'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CircleInvitePage(circleId: circle.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_add_alt_1,
              size: 16,
              color: AppColors.primaryPale,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                manager ? 'Add or invite friends' : 'Invite friends',
                style: AppTextStyles.fieldInput,
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}

/// Your notification switches for this Circle: mute it entirely, or choose
/// what it tells you about. A switch moves at once; if the server refuses,
/// it moves back and says why.
class _NotificationSettings extends ConsumerStatefulWidget {
  const _NotificationSettings({required this.circle});

  final CircleDetail circle;

  @override
  ConsumerState<_NotificationSettings> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  late CircleNotificationSettings _shown = _fromServer;

  CircleNotificationSettings get _fromServer =>
      widget.circle.summary.myNotifications ??
      const CircleNotificationSettings();

  @override
  void didUpdateWidget(covariant _NotificationSettings old) {
    super.didUpdateWidget(old);
    // The server's answer (after a save, or a refresh) is the truth.
    _shown = _fromServer;
  }

  Future<void> _change(
    CircleNotificationSettings next, {
    bool? muted,
    bool? posts,
    bool? replies,
    bool? mentions,
  }) async {
    final before = _shown;
    setState(() => _shown = next);
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(circleSettingsProvider.notifier)
        .change(
          widget.circle.id,
          muted: muted,
          posts: posts,
          replies: replies,
          mentions: mentions,
        );
    if (error == null) return;
    if (mounted) setState(() => _shown = before);
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _shown;
    // Muted means nothing at all, so the finer switches rest while it is.
    ValueChanged<bool>? unlessMuted(ValueChanged<bool> change) =>
        s.muted ? null : change;
    return Column(
      children: [
        SettingsSwitchRow(
          key: const ValueKey('circle-mute'),
          title: 'Mute this circle',
          subtitle: 'No notifications from it at all',
          value: s.muted,
          onChanged: (on) => _change(s.copyWith(muted: on), muted: on),
        ),
        SettingsSwitchRow(
          key: const ValueKey('circle-notify-posts'),
          title: 'New posts',
          subtitle: 'New posts, and comments on your posts',
          value: s.posts,
          onChanged: unlessMuted(
            (on) => _change(s.copyWith(posts: on), posts: on),
          ),
        ),
        SettingsSwitchRow(
          key: const ValueKey('circle-notify-replies'),
          title: 'Replies',
          subtitle: 'Replies to your comments',
          value: s.replies,
          onChanged: unlessMuted(
            (on) => _change(s.copyWith(replies: on), replies: on),
          ),
        ),
        SettingsSwitchRow(
          key: const ValueKey('circle-notify-mentions'),
          title: 'Mentions',
          subtitle: 'When someone mentions you',
          value: s.mentions,
          onChanged: unlessMuted(
            (on) => _change(s.copyWith(mentions: on), mentions: on),
          ),
        ),
      ],
    );
  }
}

/// Leaving the Circle. The warning says what will actually happen: your
/// posts stay; an owner hands it on (to whom is named); the last member
/// takes it with them.
class _LeaveRow extends ConsumerWidget {
  const _LeaveRow({required this.circle});

  final CircleDetail circle;

  String _warning(String? me) {
    final private = circle.summary.visibility != CircleVisibility.public;
    final rejoin = private
        ? ' To come back you will need to be approved again.'
        : '';
    if (circle.myRole?.isOwner != true) {
      return 'You will stop seeing its posts. Your own posts stay in it.'
          '$rejoin';
    }
    final heir = me == null ? null : circleSuccessor(circle.members, me);
    if (heir == null) {
      return "You're the only member, so the circle and every post in it "
          'will be deleted. Nobody can undo this.';
    }
    return "You're the owner. ${heir.user.displayName} "
        '(${heir.role.label.toLowerCase()}) becomes the owner. Your own '
        'posts stay in it.$rejoin';
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentAccountIdProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'Leave ${circle.name}?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
        ),
        content: Text(_warning(me), style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text('Stay', style: AppTextStyles.linkText),
          ),
          TextButton(
            key: const ValueKey('circle-leave-confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text('Leave', style: AppTextStyles.linkText),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await ref
          .read(circleLeaveProvider.notifier)
          .leave(circle.id);
      // Back past the Circle too: you are no longer in it.
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result?.circleDeleted == true
                ? '${circle.name} was deleted.'
                : 'You left ${circle.name}.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      key: const ValueKey('circle-leave'),
      onTap: () => _leave(context, ref),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.logout, size: 16, color: AppColors.rustPale),
            const SizedBox(width: 10),
            Text(
              'Leave this circle',
              style: AppTextStyles.fieldInput.copyWith(
                color: AppColors.rustPale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deleting a Circle, for its Owner. The name has to be typed back.
class _DangerRow extends ConsumerWidget {
  const _DangerRow({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await _confirm(context, circle.name);
        if (confirmed != true || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        try {
          await ref
              .read(circleServiceProvider)
              .delete(circle.id, confirmName: circle.name);
          navigator.pop(true);
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.rust, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 16, color: AppColors.rustPale),
            const SizedBox(width: 10),
            Text(
              'Delete this circle',
              style: AppTextStyles.fieldInput.copyWith(
                color: AppColors.rustPale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the Circle's name before deleting it, so a stray tap cannot
/// destroy a community.
Future<bool?> _confirm(BuildContext context, String name) {
  final controller = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        'Delete this circle?',
        style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Every post in it goes too, and nobody can undo it. '
            'Type the name to confirm.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            style: AppTextStyles.fieldInput,
            cursorColor: AppColors.primaryPale,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
              hintText: name,
              hintStyle: AppTextStyles.fieldInput.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel', style: AppTextStyles.linkText),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            controller.text.trim().toLowerCase() == name.trim().toLowerCase(),
          ),
          child: Text('Delete', style: AppTextStyles.linkText),
        ),
      ],
    ),
  );
}
