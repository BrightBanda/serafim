import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Who to add: chosen friends, plus anyone typed by username or UID. The
/// server checks every one (existence and their group-add privacy).
class MemberSelection {
  const MemberSelection({this.userIds = const {}, this.typed = const []});

  final Set<String> userIds;

  /// Exactly as typed (a username, @username or UID).
  final List<String> typed;

  bool get isEmpty => userIds.isEmpty && typed.isEmpty;

  /// Typed UIDs go as ids, everything else as usernames.
  ({List<String> userIds, List<String> usernames}) split() {
    final ids = {...userIds};
    final names = <String>[];
    for (final t in typed) {
      final v = t.trim();
      if (_uuid.hasMatch(v)) {
        ids.add(v.toLowerCase());
      } else {
        names.add(v.replaceFirst('@', ''));
      }
    }
    return (userIds: ids.toList(), usernames: names);
  }
}

/// Pick people from your friends list, or add them by username or UID.
class MemberPicker extends ConsumerStatefulWidget {
  const MemberPicker({
    super.key,
    required this.onChanged,
    this.exclude = const {},
  });

  final ValueChanged<MemberSelection> onChanged;

  /// Already in the group (shown as such, not selectable).
  final Set<String> exclude;

  @override
  ConsumerState<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends ConsumerState<MemberPicker> {
  final _field = TextEditingController();
  final Set<String> _ids = {};
  final List<String> _typed = [];

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _emit() =>
      widget.onChanged(MemberSelection(userIds: {..._ids}, typed: [..._typed]));

  void _addTyped() {
    final v = _field.text.trim();
    if (v.isEmpty || _typed.contains(v)) return;
    setState(() => _typed.add(v));
    _field.clear();
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsViewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ADD BY USERNAME OR UID', style: AppTextStyles.fieldLabel),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  border: Border.all(color: AppColors.lineSoft, width: 1.5),
                ),
                child: TextField(
                  controller: _field,
                  autocorrect: false,
                  onSubmitted: (_) => _addTyped(),
                  style: AppTextStyles.fieldInput.copyWith(fontSize: 12),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '@username or UID',
                    hintStyle: AppTextStyles.fieldInput.copyWith(
                      fontSize: 12,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _addTyped,
              child: Text('Add', style: AppTextStyles.linkText),
            ),
          ],
        ),
        if (_typed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _typed)
                InputChip(
                  label: Text(
                    t,
                    style: AppTextStyles.body.copyWith(fontSize: 11),
                  ),
                  backgroundColor: AppColors.paperRaised,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: AppColors.lineSoft),
                  ),
                  onDeleted: () {
                    setState(() => _typed.remove(t));
                    _emit();
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text('FROM YOUR FRIENDS', style: AppTextStyles.fieldLabel),
        const SizedBox(height: 6),
        if (!friends.hasData)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: friends.error != null
                  ? Text(
                      "Couldn't load your friends. You can still add people "
                      'by username or UID.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.smallDim,
                    )
                  : SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
            ),
          )
        else if (friends.friends.isEmpty)
          Text(
            'No friends yet — add people by username or UID above.',
            style: AppTextStyles.smallDim,
          )
        else
          for (final f in friends.friends) _friendRow(f),
      ],
    );
  }

  Widget _friendRow(PublicUser f) {
    final already = widget.exclude.contains(f.id);
    final selected = _ids.contains(f.id);
    return CheckboxListTile(
      value: already || selected,
      onChanged: already
          ? null
          : (v) {
              setState(() => v == true ? _ids.add(f.id) : _ids.remove(f.id));
              _emit();
            },
      activeColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      secondary: AvatarThumb(
        size: 34,
        imageProvider: avatarImage(f.profilePic),
      ),
      title: Text(
        f.displayName,
        style: AppTextStyles.body.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        already ? 'Already in the group' : '@${f.username}',
        style: AppTextStyles.smallDim,
      ),
    );
  }
}

/// Says what happened to each person: added, already a member, blocked by
/// their privacy setting (with the reason), or not found.
Future<void> showAddResults(BuildContext context, List<AddResult> results) {
  if (results.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.paperAlt,
      title: Text(
        'Adding members',
        style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in results)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (r.status) {
                        AddStatus.added => Icons.check_circle_outline,
                        AddStatus.alreadyMember => Icons.info_outline,
                        AddStatus.blocked => Icons.lock_outline,
                        AddStatus.notFound => Icons.help_outline,
                      },
                      size: 18,
                      color: r.status == AddStatus.added
                          ? AppColors.tealPale
                          : r.status == AddStatus.blocked
                          ? AppColors.rustPale
                          : AppColors.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.message,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
