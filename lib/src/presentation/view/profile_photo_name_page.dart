import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/avatar_picker.dart';
import 'package:serafim/src/utils/progress_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// Onboarding Step 2 — photo + display name only. Reuses SerafimTopBar,
/// SerafimTextField and SerafimButton from the signup flow.
///
/// UI only: the 0/24 character counter is local visual state (same
/// category as the password show/hide toggle) — [onContinue], [onSkip]
/// and [onBack] are plain callbacks with no logic behind them here.
class ProfilePhotoNamePage extends StatefulWidget {
  const ProfilePhotoNamePage({
    super.key,
    this.nameController,
    this.onBack,
    this.onEditPhoto,
    this.onUploadPhoto,
    this.onContinue,
    this.onSkip,
  });

  final TextEditingController? nameController;
  final VoidCallback? onBack;
  final VoidCallback? onEditPhoto;
  final VoidCallback? onUploadPhoto;
  final VoidCallback? onContinue;
  final VoidCallback? onSkip;

  @override
  State<ProfilePhotoNamePage> createState() => _ProfilePhotoNamePageState();
}

class _ProfilePhotoNamePageState extends State<ProfilePhotoNamePage> {
  late final TextEditingController _nameController =
      widget.nameController ?? TextEditingController();
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      setState(() => _charCount = _nameController.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        onBack: widget.onBack,
        trailing: Text('STEP 2 OF 3', style: AppTextStyles.fieldLabel),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const ProgressBar(progress: 0.66),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SET UP PROFILE', style: AppTextStyles.eyebrow),
                    const SizedBox(height: 6),
                    Text(
                      'Add a photo & name',
                      style: AppTextStyles.displayHeading.copyWith(
                        fontSize: 23,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This is how people will recognize you across the feed and in chat.',
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: 22),

                    Center(
                      child: AvatarPicker(
                        onEditTap: widget.onEditPhoto,
                        onUploadTap: widget.onUploadPhoto,
                      ),
                    ),
                    const SizedBox(height: 22),

                    UiTextField(
                      label: 'Display name',
                      controller: _nameController,
                      hintText: 'How should people see you?',
                      footer: Text(
                        '$_charCount / 24',
                        style: AppTextStyles.fieldLabel.copyWith(fontSize: 8.5),
                      ),
                    ),
                    const SizedBox(height: 22),

                    SerafimButton(
                      label: 'Continue',
                      onPressed: widget.onContinue,
                    ),
                    const SizedBox(height: 14),

                    Center(
                      child: GestureDetector(
                        onTap: widget.onSkip,
                        child: RichText(
                          text: TextSpan(
                            style: AppTextStyles.smallDim,
                            children: [
                              const TextSpan(text: 'Not now — '),
                              TextSpan(
                                text: 'skip this step',
                                style: AppTextStyles.linkText,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
