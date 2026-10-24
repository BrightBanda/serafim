import 'package:flutter/material.dart';
import 'package:serafim/src/utils/notification_bell.dart';
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/post.dart';
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
      // The brand bar: the Serafim logo and name.
      appBar: const AppTopBar(
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [NotificationBell(), ProfileMenuButton()],
        ),
      ),
      body: Column(
        children: [
          const _ComposeBar(),
          Expanded(child: _list(context, ref, feed)),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, AsyncValue<PostPage> feed) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.read(sparkOverridesProvider.notifier).clear();
        ref.invalidate(feedProvider);
        await ref.read(feedProvider.future);
      },
      child: feed.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
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
                          .togglePost(post, on: on),
                      onComment: () =>
                          openPost(context, post.id, focusComment: true),
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
    );
  }
}

/// The way to post, at the top of the feed: tap it and write.
class _ComposeBar extends StatelessWidget {
  const _ComposeBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ComposerPage())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(color: AppColors.lineSoft, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: AppColors.primaryPale),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Break the silence',
                  style: AppTextStyles.fieldInput.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ),
              Text(
                'POST',
                style: AppTextStyles.smallDim.copyWith(
                  color: AppColors.primaryPale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
