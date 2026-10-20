import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/relation_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';

/// A post, as it appears in a Circle, on a profile, or in the feed.
///
/// The circle's name is shown next to the author's, so a community post is
/// never mistaken for a personal one.
class PostCard extends ConsumerWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onSpark,
    this.onComment,
    this.onCircleTap,
    this.footer,
  });

  final Post post;

  /// Called with the new state: true means the post is now sparked.
  final void Function(bool sparked)? onSpark;

  /// Opens the comments.
  final VoidCallback? onComment;

  /// Opens the Circle the post belongs to.
  final VoidCallback? onCircleTap;

  /// Extra buttons under the post, for a Circle's Overseers.
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = post.circle;
    final me = ref.watch(currentAccountIdProvider);
    // Any follow tap still on its way is laid over what the server said.
    final author = watchWithPending(ref, post.author);
    final canFollow = me != null && author.id != me && !author.isFollowing;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.lineSoft, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(post: post),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.author.displayName,
                            style: AppTextStyles.fieldInput.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (circle != null) ...[
                          Text(' · ', style: AppTextStyles.smallDim),
                          Flexible(
                            child: GestureDetector(
                              onTap: onCircleTap,
                              child: Text(
                                circle.name,
                                style: AppTextStyles.smallDim.copyWith(
                                  color: AppColors.primaryPale,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        if (post.pinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: 11,
                            color: AppColors.primaryPale,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _ago(post.createdAt),
                          style: AppTextStyles.smallDim,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canFollow)
                GestureDetector(
                  onTap: () =>
                      ref.read(socialActionsProvider).follow(author.id),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primaryPale,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'FOLLOW',
                      style: AppTextStyles.smallDim.copyWith(
                        color: AppColors.primaryPale,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (post.content.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(post.content, style: AppTextStyles.fieldInput),
          ],
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            PostImages(urls: post.imageUrls),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _Action(
                icon: post.sparked ? Icons.bolt : Icons.bolt_outlined,
                label: '${post.sparkCount}',
                active: post.sparked,
                onTap: onSpark == null ? null : () => onSpark!(!post.sparked),
              ),
              const SizedBox(width: 8),
              _Action(
                icon: Icons.mode_comment_outlined,
                label: '${post.commentCount}',
                onTap: onComment,
              ),
              const Spacer(),
              if (footer != null) footer!,
            ],
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime when) {
    final diff = DateTime.now().toUtc().difference(when);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${when.day}/${when.month}/${when.year}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final image = avatarImage(post.author.profilePic);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.line, width: 1.5),
        shape: BoxShape.circle,
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image == null
          ? Text(
              post.author.displayName.characters.first.toUpperCase(),
              style: AppTextStyles.smallDim.copyWith(
                color: AppColors.primaryPale,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primaryPale : AppColors.textDim;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: color),
          if (label != '0') ...[
            const SizedBox(width: 5),
            Text(label, style: AppTextStyles.smallDim.copyWith(color: color)),
          ],
        ],
      ),
    );
  }
}

/// A post's pictures: one large, or a grid of two to four. Tap to look closer.
class PostImages extends StatelessWidget {
  const PostImages({super.key, required this.urls});

  final List<String> urls;

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ImageViewer(urls: urls, initial: index),
      ),
    );
  }

  Widget _tile(BuildContext context, int i, {double? aspect}) {
    final image = GestureDetector(
      onTap: () => _open(context, i),
      child: CachedNetworkImage(
        imageUrl: urls[i],
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(color: AppColors.paperRaised),
        errorWidget: (_, __, ___) => Container(
          color: AppColors.paperRaised,
          child: Icon(Icons.broken_image_outlined, color: AppColors.textDim),
        ),
      ),
    );
    return aspect == null
        ? image
        : AspectRatio(aspectRatio: aspect, child: image);
  }

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) return _tile(context, 0, aspect: 4 / 3);
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [for (var i = 0; i < urls.length; i++) _tile(context, i)],
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.urls, required this.initial});

  final List<String> urls;
  final int initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: urls.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(child: CachedNetworkImage(imageUrl: urls[i])),
        ),
      ),
    );
  }
}
