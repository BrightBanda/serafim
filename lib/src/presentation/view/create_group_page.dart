import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/avatar_picker.dart';
import 'package:serafim/src/utils/group_nav.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/member_picker.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// New group: photo, name, optional rules, and members (friends, usernames
/// or UIDs).
class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _name = TextEditingController();
  final _rules = TextEditingController();
  MemberSelection _members = const MemberSelection();
  Uint8List? _photo;
  bool _picking = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final bytes = await pickShrunkImage(
      context,
      maxSide: 512,
      quality: 80,
      onPicked: () => setState(() => _picking = true),
    );
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (bytes != null) _photo = bytes;
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final actions = ref.read(groupActionsProvider);
    final parts = _members.split();
    final out = await actions.create(
      name: name,
      rules: _rules.text.trim(),
      memberIds: parts.userIds,
      photo: _photo,
    );
    var results = out.results;
    String? memberAddError;
    // Usernames are added after creation (the create call takes ids).
    final group = out.group;
    if (group != null && parts.usernames.isNotEmpty) {
      final more = await actions.addMembers(
        group.id,
        usernames: parts.usernames,
      );
      results = [...results, ...more.results];
      memberAddError = more.error;
    }
    if (!mounted) return;
    if (group == null) {
      setState(() {
        _saving = false;
        _error = out.error;
      });
      return;
    }
    if (out.error != null || memberAddError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            memberAddError != null
                ? 'Group created, but those usernames could not be added: '
                      '$memberAddError'
                : out.error!,
          ),
          backgroundColor: AppColors.rust,
        ),
      );
    }
    if (results.any((r) => r.status != AddStatus.added)) {
      await showAddResults(context, results);
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    openGroupChatWithNavigator(navigator, group.summary);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'NEW GROUP',
        onBack: _saving ? null : () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: AvatarPicker(
                size: 80,
                imageProvider: _photo == null ? null : MemoryImage(_photo!),
                busy: _picking,
                busyLabel: 'Preparing…',
                onEditTap: _pickPhoto,
                onUploadTap: _pickPhoto,
              ),
            ),
            const SizedBox(height: 18),
            UiTextField(
              label: 'Group name',
              controller: _name,
              hintText: 'What is this group called?',
              maxLength: GroupLimits.nameMax,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            UiTextField(
              label: 'Rules (optional)',
              controller: _rules,
              hintText: 'Shown to every member when they join',
              maxLength: GroupLimits.rulesMax,
              maxLines: 5,
              minLines: 2,
              autocorrect: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 18),
            Text('MEMBERS', style: AppTextStyles.eyebrow),
            const SizedBox(height: 4),
            Text(
              "People who don't allow being added (in their privacy settings) "
              "will be skipped, and you'll be told why.",
              style: AppTextStyles.smallDim,
            ),
            const SizedBox(height: 12),
            MemberPicker(onChanged: (s) => _members = s),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
              ),
            ],
            const SizedBox(height: 22),
            SerafimButton(
              label: _saving ? 'Creating…' : 'Create group',
              onPressed: _saving || _picking ? null : _create,
            ),
          ],
        ),
      ),
    );
  }
}
