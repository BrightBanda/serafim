import 'dart:async';
import 'package:serafim/src/core/errors/human_error.dart';

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/notification_bell.dart';
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// Find people: suggestions ranked by shared interests, pending friend
/// requests, and search by username or UID.
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  static const _debounce = Duration(milliseconds: 350);

  final TextEditingController _controller = TextEditingController();
  Timer? _timer;

  /// The debounced, trimmed query driving the search request.
  String _query = '';
  bool _refreshing = false;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // Clear button visibility.
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

  Future<void> _refresh() async {
    if (_refreshing) return; // One refresh at a time.
    _refreshing = true;
    try {
      await Future.wait([
        ref.refresh(discoverProvider.future),
        ref.refresh(friendRequestsProvider.future),
        ref.refresh(friendsProvider.future),
      ]);
    } catch (_) {
      // The providers now hold the error and the list shows it.
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const AppTopBar(
        title: 'DISCOVER',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [NotificationBell(), ProfileMenuButton()],
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
            Expanded(
              child: _query.isEmpty
                  ? _Suggestions(onRefresh: _refresh)
                  : _SearchResults(query: _query),
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
                textInputAction: TextInputAction.search,
                autocorrect: false,
                style: AppTextStyles.fieldInput.copyWith(fontSize: 12),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Search by username or UID',
                  hintStyle: AppTextStyles.fieldInput.copyWith(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: AppColors.textDim),
              ),
          ],
        ),
      ),
    );
  }
}

/// How many people Discover shows at first, and how many more each "Show
/// more" adds.
const discoverPageSize = 10;

class _Suggestions extends ConsumerStatefulWidget {
  const _Suggestions({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends ConsumerState<_Suggestions> {
  int _shown = discoverPageSize;

  Future<void> Function() get onRefresh => widget.onRefresh;

  @override
  Widget build(BuildContext context) {
    final discover = ref.watch(discoverProvider);
    final requests = ref.watch(friendRequestsProvider).value;
    final incoming = requests?.incoming ?? const <PublicUser>[];

    // Always scrollable so pull-to-refresh also works on short or empty lists.
    Widget scrollable(List<Widget> children) => RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.paperRaised,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        children: children,
      ),
    );

    return discover.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (error, _) => scrollable([
        const SizedBox(height: 60),
        _Message(
          icon: Icons.cloud_off_outlined,
          text: humanError(error),
          actionLabel: 'Try again',
          onAction: onRefresh,
        ),
      ]),
      data: (people) {
        final children = <Widget>[
          if (incoming.isNotEmpty) ...[
            Text('FRIEND REQUESTS', style: AppTextStyles.eyebrow),
            const SizedBox(height: 8),
            for (final user in incoming) ...[
              UserCard(user: user),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],
          Text('SUGGESTED FOR YOU', style: AppTextStyles.eyebrow),
          const SizedBox(height: 8),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: _Message(
                icon: Icons.explore_outlined,
                text: 'No one new to show right now.\nPull down to refresh.',
              ),
            )
          else ...[
            for (final user in people.take(_shown)) ...[
              UserCard(user: user),
              const SizedBox(height: 10),
            ],
            if (people.length > _shown)
              _ShowMore(
                remaining: people.length - _shown,
                onTap: () => setState(() => _shown += discoverPageSize),
              ),
          ],
        ];
        return scrollable(children);
      },
    );
  }
}

/// "Show more" at the bottom of a list that has been cut short.
class _ShowMore extends StatelessWidget {
  const _ShowMore({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        child: Text('Show more ($remaining)', style: AppTextStyles.linkText),
      ),
    );
  }
}

class _SearchResults extends ConsumerStatefulWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  ConsumerState<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends ConsumerState<_SearchResults> {
  int _shown = discoverPageSize;

  String get query => widget.query;

  @override
  void didUpdateWidget(_SearchResults old) {
    super.didUpdateWidget(old);
    // A new search starts again from the top ten.
    if (old.query != widget.query) _shown = discoverPageSize;
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(userSearchProvider(query));

    return results.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (error, _) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const SizedBox(height: 60),
          _Message(
            icon: Icons.cloud_off_outlined,
            text: humanError(error),
            actionLabel: 'Try again',
            onAction: () async => ref.invalidate(userSearchProvider(query)),
          ),
        ],
      ),
      data: (people) {
        if (people.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const SizedBox(height: 60),
              _Message(
                icon: Icons.search_off,
                text: 'No one found for "$query".\nCheck the username or UID.',
              ),
            ],
          );
        }
        final shown = people.take(_shown).toList();
        final more = people.length - shown.length;
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: shown.length + (more > 0 ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => i < shown.length
              ? UserCard(user: shown[i])
              : _ShowMore(
                  remaining: more,
                  onTap: () => setState(() => _shown += discoverPageSize),
                ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 32, color: AppColors.textDim),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: AppTextStyles.body),
        if (actionLabel != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: onAction == null ? null : () => onAction!(),
            child: Text(actionLabel!, style: AppTextStyles.linkText),
          ),
        ],
      ],
    );
  }
}
