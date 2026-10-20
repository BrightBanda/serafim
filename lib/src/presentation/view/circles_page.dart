import 'dart:async';

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/presentation/view/circle_detail_page.dart';
import 'package:serafim/src/presentation/view/create_circle_page.dart';
import 'package:serafim/src/presentation/view/widgets/circle_card.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The Circles tab: Circles to try, popular ones, and the ones you have
/// joined.
class CirclesPage extends ConsumerStatefulWidget {
  const CirclesPage({super.key});

  @override
  ConsumerState<CirclesPage> createState() => _CirclesPageState();
}

class _CirclesPageState extends ConsumerState<CirclesPage> {
  static const _debounce = Duration(milliseconds: 350);

  final TextEditingController _controller = TextEditingController();
  Timer? _timer;

  String _query = '';
  String _section = 'for_you';
  String? _category;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  void _setSection(String section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  void _setCategory(String? category) {
    if (_category == category) return;
    setState(() => _category = category);
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<CircleDetail>(
      MaterialPageRoute<CircleDetail>(builder: (_) => const CreateCirclePage()),
    );
    if (created != null && mounted) {
      // The Circle is open, ready to post in.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CircleDetailPage(circleId: created.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = DiscoverCirclesQuery(
      section: _section,
      category: _category,
      query: _query,
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'CIRCLES',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _openCreate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  border: Border.all(color: AppColors.line, width: 1.5),
                ),
                child: Text(
                  'NEW',
                  style: AppTextStyles.buttonLabel.copyWith(fontSize: 11),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const ProfileMenuButton(),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SearchField(
              controller: _controller,
              onChanged: _onChanged,
              onClear: _clear,
            ),
            _SectionTabs(section: _section, onChanged: _setSection),
            if (_section == 'popular')
              _CategoryStrip(selected: _category, onChanged: _setCategory),
            Expanded(
              child: _query.isEmpty
                  ? _JoinedAndSuggestions(query: query)
                  : _DiscoverList(query: query),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: AppTextStyles.fieldInput,
                cursorColor: AppColors.primaryPale,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search circles',
                  hintStyle: AppTextStyles.fieldInput.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 15, color: AppColors.textDim),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.section, required this.onChanged});

  final String section;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = [('for_you', 'For you'), ('popular', 'Popular')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          for (final (value, label) in tabs) ...[
            GestureDetector(
              onTap: () => onChanged(value),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: section == value
                      ? AppColors.paperRaised
                      : Colors.transparent,
                  border: Border.all(
                    color: section == value
                        ? AppColors.primary
                        : AppColors.lineSoft,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.fieldLabel.copyWith(
                    color: section == value
                        ? AppColors.primaryPale
                        : AppColors.textDim,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _CategoryChip(
            label: 'All',
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final category in circleCategories)
            _CategoryChip(
              label: category,
              selected: selected == category,
              onTap: () => onChanged(category),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.lineSoft,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.fieldLabel.copyWith(
              color: selected ? AppColors.primaryPale : AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Circles you have joined, and the ones worth trying.
class _JoinedAndSuggestions extends ConsumerWidget {
  const _JoinedAndSuggestions({required this.query});

  final DiscoverCirclesQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = ref.watch(myCirclesProvider);
    final suggestions = ref.watch(discoverCirclesProvider(query));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _Label('JOINED'),
        const SizedBox(height: 6),
        joined.when(
          loading: () => const _Hint('Loading your circles…'),
          error: (e, _) => _Hint(humanError(e)),
          data: (circles) => circles.isEmpty
              ? const _Hint('You have not joined any circles yet.')
              : Column(
                  children: [
                    for (final circle in circles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CircleTile(circle: circle),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        _Label('FOR YOU'),
        const SizedBox(height: 6),
        suggestions.when(
          loading: () => const _Hint('Looking for circles…'),
          error: (e, _) => _Hint(humanError(e)),
          data: (circles) => circles.isEmpty
              ? const _Hint(
                  'Nothing to suggest yet. Add interests to your profile and '
                  'more circles will show up here.',
                )
              : Column(
                  children: [
                    for (final circle in circles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CircleTile(circle: circle),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Just the search results.
class _DiscoverList extends ConsumerWidget {
  const _DiscoverList({required this.query});

  final DiscoverCirclesQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(discoverCirclesProvider(query));
    return found.when(
      loading: () => const _Hint('Looking for circles…'),
      error: (e, _) => _Hint(humanError(e)),
      data: (circles) => circles.isEmpty
          ? const _Hint('No circles match that.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                for (final circle in circles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CircleTile(circle: circle),
                  ),
              ],
            ),
    );
  }
}

/// A Circle card, with its join button wired up.
class _CircleTile extends ConsumerStatefulWidget {
  const _CircleTile({required this.circle});

  final CircleSummary circle;

  @override
  ConsumerState<_CircleTile> createState() => _CircleTileState();
}

class _CircleTileState extends ConsumerState<_CircleTile> {
  bool _busy = false;

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(circleJoinProvider.notifier).join(widget.circle.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final circle = widget.circle;
    final canJoin =
        !circle.isMember &&
        !circle.iAmBanned &&
        circle.visibility != CircleVisibility.inviteOnly;

    return CircleCard(
      circle: circle,
      onOpen: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CircleDetailPage(circleId: circle.id),
        ),
      ),
      onJoin: canJoin ? _join : null,
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.eyebrow.copyWith(fontSize: 9));
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text, style: AppTextStyles.smallDim),
    );
  }
}
