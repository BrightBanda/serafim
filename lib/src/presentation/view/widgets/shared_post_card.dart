import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// A post shared into a chat: its heading, who wrote it, and a small preview
/// of its first picture. Tapping it opens the post.
///
/// The message only holds the post's id; the post is fetched with the
/// reader's own account, so someone who may not see it (a private Circle, a
/// deleted post) is told it is not available rather than shown it.
class SharedPostCard extends ConsumerWidget {
  const SharedPostCard({
    super.key,
    required this.postId,
    required this.outgoing,
    this.onLongPress,
  });

  final String postId;
  final bool outgoing;
  final VoidCallback? onLongPress;

  static const thumbSize = 56.0;

  /// The line to show as the heading: the title, else the start of the text.
  static String headingOf(Post post) {
    final title = post.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final text = post.content.trim();
    if (text.isNotEmpty) return text.split('\n').first;
    return post.imageUrls.isNotEmpty ? 'Photo' : 'Post';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId));
    final Widget body = switch (post) {
      AsyncData(:final value) => _Loaded(post: value),
      AsyncError() => const _Unavailable(),
      _ => const _Loading(),
    };
    return GestureDetector(
      key: ValueKey('shared-post-$postId'),
      behavior: HitTestBehavior.opaque,
      onTap: post.hasValue ? () => openPost(context, postId) : null,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.paper.withValues(alpha: 0.6),
          border: Border(
            left: BorderSide(color: AppColors.primaryPale, width: 3),
          ),
        ),
        child: body,
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final images = post.imageUrls;
    final where = post.circle == null ? '' : ' · ${post.circle!.name}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 13,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${post.author.displayName}$where',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.smallDim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                SharedPostCard.headingOf(post),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.fieldInput.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap to open',
                style: AppTextStyles.smallDim.copyWith(
                  color: AppColors.primaryPale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (images.isNotEmpty) ...[
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: SharedPostCard.thumbSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: images.first,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.paperRaised),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.paperRaised,
                    child: Icon(
                      Icons.image_outlined,
                      size: 18,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
                if (images.length > 1)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      color: Colors.black.withValues(alpha: 0.6),
                      child: Text(
                        '+${images.length - 1}',
                        style: AppTextStyles.smallDim.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SharedPostCard.thumbSize,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryPale,
            ),
          ),
          const SizedBox(width: 10),
          Text('Loading post…', style: AppTextStyles.smallDim),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.lock_outline, size: 16, color: AppColors.textDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "This post isn't available. It may have been deleted, or be in "
            "a Circle you're not in.",
            style: AppTextStyles.smallDim,
          ),
        ),
      ],
    );
  }
}
