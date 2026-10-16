import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// People you follow, or who follow you. [provider] decides which.
class FollowListPage extends ConsumerWidget {
  const FollowListPage({
    super.key,
    required this.title,
    required this.provider,
    required this.emptyText,
  });

  final String title;
  final FutureProvider<List<PublicUser>> provider;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(provider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: title,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.paperRaised,
          onRefresh: () async {
            ref.invalidate(provider);
            try {
              await ref.read(provider.future);
            } catch (_) {}
          },
          child: people.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (error, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 60),
                Text(
                  humanError(error),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.rustPale,
                  ),
                ),
              ],
            ),
            data: (list) => list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 60),
                      Text(
                        emptyText,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => UserCard(user: list[i]),
                  ),
          ),
        ),
      ),
    );
  }
}
