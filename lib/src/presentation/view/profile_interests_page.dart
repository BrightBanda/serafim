import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/category_section.dart';
import 'package:serafim/src/utils/progress_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/serafim_chip.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Onboarding Step 3 — interests, grouped into Sports / Hobbies /
/// Entertainment. Reuses SerafimTopBar and SerafimButton.
///
/// UI only: which chips are selected is local visual state (same
/// category as a checkbox's checked state) — [onFinish] and [onSkip]
/// are plain callbacks, nothing is persisted or submitted here.
class ProfileInterestsPage extends StatefulWidget {
  const ProfileInterestsPage({
    super.key,
    this.onBack,
    this.onFinish,
    this.onSkip,
  });

  final VoidCallback? onBack;

  /// Receives the chosen interests — the page owns the selection, so it has
  /// to hand it out rather than expect the caller to read it back.
  final ValueChanged<Set<String>>? onFinish;

  /// Same, with whatever happens to be selected; skipping means "no
  /// interests", not "abandon setup".
  final ValueChanged<Set<String>>? onSkip;

  @override
  State<ProfileInterestsPage> createState() => _ProfileInterestsPageState();
}

class _ProfileInterestsPageState extends State<ProfileInterestsPage> {
  final Set<String> _selected = {};

  static const _categories = <String, List<String>>{
    'Sports': [
      'Soccer',
      'Basketball',
      'Running',
      'Cycling',
      'Swimming',
      'Tennis',
    ],
    'Hobbies': [
      'Gaming',
      'Cooking',
      'Photography',
      'Reading',
      'Stargazing',
      'Gardening',
    ],
    'Entertainment': ['Movies', 'Music', 'Anime', 'Podcasts', 'Comics'],
  };

  static const _categoryIcons = <String, IconData>{
    'Sports': Icons.sports_soccer_outlined,
    'Hobbies': Icons.auto_awesome_outlined,
    'Entertainment': Icons.movie_outlined,
  };

  void _toggle(String label) {
    setState(() {
      _selected.contains(label)
          ? _selected.remove(label)
          : _selected.add(label);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        onBack: widget.onBack,
        trailing: Text('STEP 3 OF 3', style: AppTextStyles.fieldLabel),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const ProgressBar(progress: 1.0),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LAST STEP', style: AppTextStyles.eyebrow),
                    const SizedBox(height: 6),
                    Text(
                      'What are you into?',
                      style: AppTextStyles.displayHeading.copyWith(
                        fontSize: 23,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We'll use these to find people, groups, and posts near your interests.",
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: 10),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_selected.length} selected',
                        style: AppTextStyles.fieldLabel.copyWith(
                          color: AppColors.primaryPale,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    for (final entry in _categories.entries) ...[
                      CategorySection(
                        title: entry.key,
                        icon: _categoryIcons[entry.key]!,
                        children: [
                          for (final label in entry.value)
                            SerafimChip(
                              label: label,
                              selected: _selected.contains(label),
                              onTap: () => _toggle(label),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],

                    SerafimButton(
                      label: 'Finish setup',
                      onPressed: widget.onFinish == null
                          ? null
                          : () => widget.onFinish!(_selected),
                    ),
                    const SizedBox(height: 14),

                    Center(
                      child: GestureDetector(
                        onTap: widget.onSkip == null
                            ? null
                            : () => widget.onSkip!(_selected),
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
