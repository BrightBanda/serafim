import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/config/feature_flags.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/presentation/view/post_list_page.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// A person's posts, for the bottom of their profile. Shows nothing when
/// posts are switched off.
///
/// What the server sends already respects who may see what: Circle posts the
/// viewer is not allowed to read are not in the list.
class ProfilePosts extends ConsumerWidget {
  const ProfilePosts({super.key, required this.userId});

  final String userId;

  /// A profile shows the latest few; "See all" opens the rest.
  static const shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!FeatureFlags.posts) return const SizedBox.shrink();
    final posts = ref.watch(authorPostsProvider(userId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text('POSTS', style: AppTextStyles.eyebrow),
        const SizedBox(height: 8),
        posts.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(humanError(e), style: AppTextStyles.body),
          data: (page) {
            if (page.items.isEmpty) {
              return Text('No posts yet.', style: AppTextStyles.body);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final post in page.items.take(shown))
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
                if (page.items.length > shown || page.hasMore)
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PostListPage(userId: userId),
                        ),
                      ),
                      child: Text('See all', style: AppTextStyles.linkText),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
