import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/presentation/view/widgets/load_more_button.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Every post by one person ("See all" on a profile).
class PostListPage extends ConsumerWidget {
  const PostListPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(authorPostsProvider(userId));
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'POSTS',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: posts.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) =>
            Center(child: Text(humanError(e), style: AppTextStyles.body)),
        data: (page) => ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (page.items.isEmpty)
              Text('No posts yet.', style: AppTextStyles.body),
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
                onLoad: ref.read(authorPostsProvider(userId).notifier).loadMore,
              ),
          ],
        ),
      ),
    );
  }
}
