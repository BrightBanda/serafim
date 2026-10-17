import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/config/profile_limits.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/interest_picker.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// Change display name, username, bio and interests. Only fields that
/// actually changed are sent. This page only ever edits the signed-in user's
/// own profile (`PUT /profile/me`).
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.displayName,
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.profile.username,
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.profile.bio ?? '',
  );
  late Set<String> _interests = {...widget.profile.interests};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _interestsChanged {
    final before = widget.profile.interests.map((e) => e.toLowerCase()).toSet();
    final after = _interests.map((e) => e.toLowerCase()).toSet();
    return before.length != after.length || !before.containsAll(after);
  }

  Future<void> _save() async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final username = _username.text.trim().toLowerCase();
    final bio = _bio.text.trim();

    final problem =
        ProfileLimits.displayNameError(name) ??
        ProfileLimits.usernameError(username) ??
        ProfileLimits.bioError(bio);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final request = ProfileUpdateRequest(
      displayName: name != widget.profile.displayName ? name : null,
      username: username != widget.profile.username ? username : null,
      // An empty bio is sent as "" so the server clears it.
      bio: bio != (widget.profile.bio ?? '') ? bio : null,
      interests: _interestsChanged ? _interests.toList() : null,
    );
    if (request.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await ref
        .read(profileViewModelProvider.notifier)
        .updateProfile(request);
    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'EDIT PROFILE',
        onBack: _saving ? null : () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UiTextField(
                label: 'Display name',
                controller: _name,
                hintText: 'How should people see you?',
                maxLength: ProfileLimits.displayNameMax,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              UiTextField(
                label: 'Username',
                controller: _username,
                hintText: 'letters, numbers and _',
                maxLength: ProfileLimits.usernameMax,
              ),
              const SizedBox(height: 16),
              UiTextField(
                label: 'Bio',
                controller: _bio,
                hintText: 'A line or two about you (optional)',
                maxLength: ProfileLimits.bioMax,
                maxLines: 4,
                minLines: 2,
                autocorrect: true,
                textCapitalization: TextCapitalization.sentences,
              ),
              Text(
                'Leave it empty to remove your bio.',
                style: AppTextStyles.smallDim,
              ),
              const SizedBox(height: 24),
              Text('INTERESTS', style: AppTextStyles.eyebrow),
              const SizedBox(height: 4),
              Text(
                'Shared interests are how people find each other in Discover.',
                style: AppTextStyles.smallDim,
              ),
              const SizedBox(height: 12),
              InterestPicker(
                initial: _interests,
                onChanged: (value) => _interests = value,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
                ),
              ],
              const SizedBox(height: 22),
              SerafimButton(
                label: _saving ? 'Saving…' : 'Save changes',
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
