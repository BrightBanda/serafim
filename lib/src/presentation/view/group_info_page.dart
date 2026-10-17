import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/member_picker.dart';
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// Shows a group's rules (on joining, or from the group info).
Future<void> showGroupRules(
  BuildContext context, {
  required String groupName,
  required String rules,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.paperAlt,
      title: Text(
        '$groupName · Rules',
        style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
      ),
      content: SingleChildScrollView(
        child: Text(
          rules,
          style: AppTextStyles.body.copyWith(color: AppColors.text),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

/// A group's photo, name, rules and members, with what your role allows.
class GroupInfoPage extends ConsumerWidget {
  const GroupInfoPage({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupDetailProvider(groupId));

    Widget body;
    final detail = async.value;
    if (detail != null) {
      body = _Content(detail: detail);
    } else if (async.hasError) {
      final gone =
          async.error is ApiException &&
          (async.error! as ApiException).isNotFound;
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                gone
                    ? "You're no longer a member of this group."
                    : humanError(
                        async.error,
                        fallback: "Couldn't load the group.",
                      ),
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              if (!gone)
                TextButton(
                  onPressed: () => ref.invalidate(groupDetailProvider(groupId)),
                  child: Text('Try again', style: AppTextStyles.linkText),
                ),
            ],
          ),
        ),
      );
    } else {
      body = Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'GROUP INFO',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _Content extends ConsumerStatefulWidget {
  const _Content({required this.detail});

  final GroupDetail detail;

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  bool _busy = false;

  GroupDetail get d => widget.detail;
  GroupActions get _actions => ref.read(groupActionsProvider);

  void _tell(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.rust : null,
        ),
      );
  }

  Future<void> _guard(Future<String?> Function() action, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _tell(error);
    } else if (ok != null) {
      _tell(ok, error: false);
    }
  }

  Future<String?> _ask({
    required String title,
    required String initial,
    required int maxLength,
    int maxLines = 1,
    String? hint,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          title,
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: 1,
          style: AppTextStyles.fieldInput,
          cursorColor: AppColors.primary,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _rename() async {
    final name = await _ask(
      title: 'Group name',
      initial: d.summary.name,
      maxLength: GroupLimits.nameMax,
    );
    if (name == null) return;
    if (name.trim().isEmpty) {
      _tell('A group needs a name.');
      return;
    }
    await _guard(() => _actions.updateInfo(d.id, name: name.trim()));
  }

  Future<void> _editRules() async {
    final rules = await _ask(
      title: 'Group rules',
      initial: d.rules ?? '',
      maxLength: GroupLimits.rulesMax,
      maxLines: 8,
      hint: 'Shown to everyone when they join. Leave empty for none.',
    );
    if (rules == null) return;
    await _guard(
      () => _actions.updateInfo(d.id, rules: rules.trim()),
      ok: 'Rules updated',
    );
  }

  Future<void> _changePhoto() async {
    final bytes = await pickShrunkImage(context, maxSide: 512, quality: 80);
    if (bytes == null) return;
    await _guard(() => _actions.changePhoto(d.id, bytes));
  }

  Future<void> _addMembers() async {
    var selection = const MemberSelection();
    final go = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: AppColors.paper,
          appBar: AppTopBar(
            title: 'ADD MEMBERS',
            onBack: () => Navigator.pop(ctx),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                MemberPicker(
                  exclude: {for (final m in d.members) m.user.id},
                  onChanged: (s) => selection = s,
                ),
                const SizedBox(height: 20),
                SerafimButton(
                  label: 'Add to group',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (go != true || selection.isEmpty || !mounted) return;
    final parts = selection.split();
    setState(() => _busy = true);
    final out = await _actions.addMembers(
      d.id,
      userIds: parts.userIds,
      usernames: parts.usernames,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (out.error != null) {
      _tell(out.error!);
    } else {
      await showAddResults(context, out.results);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          title,
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(body, style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _memberAction(GroupMemberInfo m, String action) async {
    final name = m.user.displayName;
    switch (action) {
      case 'admin':
        await _guard(() => _actions.setRole(d.id, m.user.id, GroupRole.admin));
      case 'member':
        await _guard(() => _actions.setRole(d.id, m.user.id, GroupRole.member));
      case 'transfer':
        if (await _confirm(
          'Make $name the owner?',
          "You'll become an admin. Only the owner can change roles or hand "
              'the group over.',
          'Transfer',
        )) {
          await _guard(() => _actions.transfer(d.id, m.user.id));
        }
      case 'remove':
        if (await _confirm(
          'Remove $name?',
          "They'll lose access to the group and its messages.",
          'Remove',
        )) {
          await _guard(() => _actions.removeMember(d.id, m.user.id));
        }
    }
  }

  Future<void> _leave() async {
    final me = ref.read(currentAccountIdProvider);
    final others = d.members.where((m) => m.user.id != me).toList();
    String? newOwner;

    if (d.summary.myRole == GroupRole.owner && others.isNotEmpty) {
      // Owners hand the group over; default to the suggested successor.
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          backgroundColor: AppColors.paperAlt,
          title: Text(
            'Who takes over?',
            style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
          ),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(
                'Choose for me (an admin first, else the longest member)',
                style: AppTextStyles.body.copyWith(color: AppColors.text),
              ),
            ),
            for (final m in others)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, m.user.id),
                child: Text(
                  '${m.user.displayName} · ${m.role.label}',
                  style: AppTextStyles.body.copyWith(color: AppColors.text),
                ),
              ),
          ],
        ),
      );
      if (picked == null) return;
      newOwner = picked.isEmpty ? null : picked;
    } else if (!await _confirm(
      'Leave ${d.summary.name}?',
      others.isEmpty
          ? "You're the last member, so the group and its messages will be "
                'deleted.'
          : "Its messages will be removed from this device.",
      'Leave',
    )) {
      return;
    }

    setState(() => _busy = true);
    final error = await _actions.leave(d.id, newOwnerId: newOwner);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _tell(error);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAccountIdProvider);
    final role = d.summary.myRole;
    final photo = avatarImage(d.summary.photoUrl);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        if (_busy)
          LinearProgressIndicator(color: AppColors.primary, minHeight: 2),
        Center(
          child: TappableAvatar(
            image: photo,
            heroTag: 'group-info:${d.id}',
            name: d.summary.name,
            size: 88,
            isGroup: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          d.summary.name,
          textAlign: TextAlign.center,
          style: AppTextStyles.displayHeading,
        ),
        Text(
          '${d.summary.memberCount} members · you are ${role.label.toLowerCase()}',
          textAlign: TextAlign.center,
          style: AppTextStyles.smallDim,
        ),
        if (role.canManage) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _rename,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Rename'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _changePhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                label: const Text('Change photo'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Text('RULES', style: AppTextStyles.eyebrow),
            const Spacer(),
            if (role.canManage)
              TextButton(
                onPressed: _busy ? null : _editRules,
                child: Text('Edit', style: AppTextStyles.linkText),
              ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(color: AppColors.lineSoft, width: 1.5),
          ),
          child: Text(
            (d.rules ?? '').isEmpty
                ? (role.canManage
                      ? 'No rules yet. Add some so new members know what to expect.'
                      : 'This group has no rules.')
                : d.rules!,
            style: (d.rules ?? '').isEmpty
                ? AppTextStyles.smallDim
                : AppTextStyles.body.copyWith(color: AppColors.text),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('MEMBERS (${d.members.length})', style: AppTextStyles.eyebrow),
            const Spacer(),
            TextButton.icon(
              onPressed: _busy ? null : _addMembers,
              icon: const Icon(Icons.person_add_alt, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        for (final m in d.members) _memberRow(m, me, role),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy ? null : _leave,
          icon: Icon(Icons.logout, size: 16, color: AppColors.rustPale),
          label: Text(
            'Leave group',
            style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.rust, width: 1.5),
            shape: const RoundedRectangleBorder(),
          ),
        ),
      ],
    );
  }

  Widget _memberRow(GroupMemberInfo m, String? me, GroupRole myRole) {
    final isMe = m.user.id == me;
    final actions = <PopupMenuEntry<String>>[
      if (myRole == GroupRole.owner && !isMe && m.role == GroupRole.member)
        const PopupMenuItem(value: 'admin', child: Text('Make admin')),
      if (myRole == GroupRole.owner && !isMe && m.role == GroupRole.admin)
        const PopupMenuItem(value: 'member', child: Text('Remove admin role')),
      if (myRole == GroupRole.owner && !isMe)
        const PopupMenuItem(value: 'transfer', child: Text('Make owner')),
      if (!isMe && myRole.canRemove(m.role))
        const PopupMenuItem(value: 'remove', child: Text('Remove from group')),
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: isMe
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UserProfilePage(userId: m.user.id),
              ),
            ),
      leading: TappableAvatar(
        image: avatarImage(m.user.profilePic),
        heroTag: 'group-member:${d.id}:${m.user.id}',
        name: m.user.displayName,
        size: 38,
      ),
      title: Text(
        isMe ? '${m.user.displayName} (you)' : m.user.displayName,
        style: AppTextStyles.body.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text('@${m.user.username}', style: AppTextStyles.smallDim),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.role != GroupRole.member)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              color: m.role == GroupRole.owner
                  ? AppColors.primary
                  : AppColors.teal,
              child: Text(
                m.role.label.toUpperCase(),
                style: AppTextStyles.fieldLabel.copyWith(
                  fontSize: 8,
                  color: Colors.white,
                ),
              ),
            ),
          if (actions.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Member options',
              color: AppColors.paperAlt,
              icon: Icon(Icons.more_vert, size: 18, color: AppColors.textDim),
              onSelected: (a) => _memberAction(m, a),
              itemBuilder: (_) => actions,
            ),
        ],
      ),
    );
  }
}
