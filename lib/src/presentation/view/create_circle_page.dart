import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/presentation/view/widgets/circle_choices.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// Creates a Circle. The creator becomes its Owner.
class CreateCirclePage extends ConsumerStatefulWidget {
  const CreateCirclePage({super.key});

  @override
  ConsumerState<CreateCirclePage> createState() => _CreateCirclePageState();
}

class _CreateCirclePageState extends ConsumerState<CreateCirclePage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _rules = TextEditingController();

  String? _category;
  CircleVisibility _visibility = CircleVisibility.public;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final circle = await ref
          .read(circleServiceProvider)
          .create(
            name: _name.text.trim(),
            description: _description.text.trim(),
            category: _category,
            visibility: _visibility,
            rules: _rules.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(circle);
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(title: 'NEW CIRCLE', onBack: _back),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
          children: [
            UiTextField(
              label: 'NAME',
              controller: _name,
              hintText: 'Flutter Developers',
              maxLength: CircleLimits.nameMax,
            ),
            const SizedBox(height: 12),
            UiTextField(
              label: 'WHAT IS IT ABOUT',
              controller: _description,
              hintText: 'A short line about who this is for.',
              maxLines: 3,
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
              maxLines: 4,
              minLines: 2,
              maxLength: CircleLimits.rulesMax,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
              ),
            ],
            const SizedBox(height: 24),
            SerafimButton(
              label: _busy ? 'CREATING…' : 'CREATE CIRCLE',
              onPressed: _busy ? null : _create,
            ),
          ],
        ),
      ),
    );
  }

  void _back() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }
}
