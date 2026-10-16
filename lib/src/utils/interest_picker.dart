import 'package:flutter/material.dart';
import 'package:serafim/src/data/interest_catalog.dart';
import 'package:serafim/src/utils/category_section.dart';
import 'package:serafim/src/utils/serafim_chip.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The categorised chip grid used by onboarding and Edit profile, plus a field
/// to add your own. Owns its selection; reports every change through
/// [onChanged]. Interests chosen earlier that aren't in the catalog (custom
/// ones) are shown in their own "Your own" group so they can be removed.
class InterestPicker extends StatefulWidget {
  const InterestPicker({
    super.key,
    this.initial = const {},
    required this.onChanged,
  });

  final Set<String> initial;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<InterestPicker> createState() => _InterestPickerState();
}

class _InterestPickerState extends State<InterestPicker> {
  late final Set<String> _selected = {...widget.initial};
  final TextEditingController _custom = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Set<String> get _catalogLabels => {
    for (final list in interestCatalog.values) ...list,
  };

  void _toggle(String label) {
    final existing = _selected.where(
      (s) => s.toLowerCase() == label.toLowerCase(),
    );
    setState(() {
      _error = null;
      if (existing.isNotEmpty) {
        _selected.removeAll(existing.toList());
      } else if (_selected.length >= maxInterests) {
        _error = 'You can pick up to $maxInterests interests.';
      } else {
        _selected.add(label);
      }
    });
    widget.onChanged({..._selected});
  }

  void _addCustom() {
    final cleaned = cleanInterest(_custom.text);
    if (cleaned == null) return;
    if (hasInterest(_selected, cleaned)) {
      setState(() => _error = '"$cleaned" is already in your list.');
      return;
    }
    if (_selected.length >= maxInterests) {
      setState(() => _error = 'You can pick up to $maxInterests interests.');
      return;
    }
    setState(() {
      _selected.add(cleaned);
      _error = null;
      _custom.clear();
    });
    widget.onChanged({..._selected});
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalogLabels.map((e) => e.toLowerCase()).toSet();
    final custom =
        _selected.where((s) => !catalog.contains(s.toLowerCase())).toList()
          ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${_selected.length} / $maxInterests selected',
            style: AppTextStyles.fieldLabel.copyWith(
              color: AppColors.primaryPale,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in interestCatalog.entries) ...[
          CategorySection(
            title: entry.key,
            icon: interestCategoryIcons[entry.key] ?? Icons.label_outline,
            children: [
              for (final label in entry.value)
                SerafimChip(
                  label: label,
                  selected: hasInterest(_selected, label),
                  onTap: () => _toggle(label),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        CategorySection(
          title: 'Your own',
          icon: Icons.add_circle_outline,
          children: [
            for (final label in custom)
              SerafimChip(
                label: label,
                selected: true,
                onTap: () => _toggle(label),
              ),
          ],
        ),
        const SizedBox(height: 8),
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
                  controller: _custom,
                  maxLength: maxInterestLength,
                  onSubmitted: (_) => _addCustom(),
                  textInputAction: TextInputAction.done,
                  style: AppTextStyles.fieldInput.copyWith(fontSize: 12),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: 'Add something else you like',
                    hintStyle: AppTextStyles.fieldInput.copyWith(
                      color: AppColors.textDim,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _addCustom,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  border: Border.all(color: AppColors.line, width: 1.5),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: AppTextStyles.smallDim.copyWith(color: AppColors.rustPale),
          ),
        ],
      ],
    );
  }
}
