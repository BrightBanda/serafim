import 'package:flutter/material.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart'
    show NotificationBell;
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/presentation/view/composer_page.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/presentation/view/widgets/load_more_button.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Posts from the people you follow and the Circles you have joined.
class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const AppTopBar(
        title: 'FEED',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [NotificationBell(), ProfileMenuButton()],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(feedProvider.future),
        child: feed.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  humanError(e),
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          data: (page) {
            if (page.items.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nothing here yet. Follow people or join a Circle.',
                      style: AppTextStyles.body,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
              children: [
                for (final post in page.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => openPost(context, post.id),
                      child: PostCard(
                        post: post,
                        onSpark: (on) => ref
                            .read(sparkProvider.notifier)
                            .togglePost(post.id, on: on),
                        onComment: () => openPost(context, post.id),
                        onCircleTap: post.circle == null
                            ? null
                            : () => openCircle(context, post.circle!.id),
                      ),
                    ),
                  ),
                if (page.hasMore)
                  LoadMoreButton(
                    onLoad: ref.read(feedProvider.notifier).loadMore,
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ComposerPage())),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}
