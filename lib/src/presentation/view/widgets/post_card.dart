import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/presentation/view/forward_page.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
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
    this.canManage = false,
    this.showFullText = false,
    this.onDeleted,
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

  /// Whether the signed-in person may remove this post — a Circle's
  /// Overseer, for example. The author may always remove their own.
  final bool canManage;

  /// Show the whole text, however long. Lists cut it at five lines with a
  /// "See more"; the post's own page shows it all.
  final bool showFullText;

  /// Called after the post has been deleted. The detail page uses it to
  /// close itself.
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = post.circle;
    final me = ref.watch(currentAccountIdProvider);
    // What the person just did shows at once; see SparkController.
    final spark =
        ref.watch(sparkOverridesProvider.select((m) => m['p:${post.id}'])) ??
        (sparked: post.sparked, count: post.sparkCount);
    // Your following list decides, not the post's own snapshot of its author
    // (see followingIdsProvider). Null only until the list first arrives.
    final isFollowing = me == null || post.author.id == me
        ? null
        : watchIsFollowing(ref, post.author);
    final canFollow = isFollowing != null;
    final following = isFollowing ?? false;
    final isMine = me != null && post.author.id == me;
    final canDelete = isMine || canManage;

    void openAuthorProfile() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfilePage(userId: post.author.id),
        ),
      );
    }

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
              _Avatar(post: post, onTap: openAuthorProfile),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: openAuthorProfile,
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              post.author.displayName,
                              style: AppTextStyles.fieldInput.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (canFollow) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            // Shows the new state at once; tapping "following"
                            // takes the follow back.
                            onTap: () => _toggleFollow(context, ref, following),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: following
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : null,
                                border: Border.all(
                                  color: following
                                      ? AppColors.lineSoft
                                      : AppColors.primaryPale,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                following ? 'FOLLOWING' : 'FOLLOW',
                                style: AppTextStyles.smallDim.copyWith(
                                  color: following
                                      ? AppColors.textDim
                                      : AppColors.primaryPale,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
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
              if (canDelete)
                PopupMenuButton<String>(
                  tooltip: 'Post options',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AppColors.textDim,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDelete(context, ref);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
            ],
          ),
          if (post.title != null && post.title!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.title!,
              style: AppTextStyles.fieldInput.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (post.content.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PostBody(text: post.content, showAll: showFullText),
          ],
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            PostImages(urls: post.imageUrls),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              // Wraps onto a second line rather than overflowing on a narrow
              // phone with long counts.
              Expanded(
                child: Wrap(
                  spacing: 12,
                  children: [
                    _Action(
                      icon: spark.sparked ? Icons.bolt : Icons.bolt_outlined,
                      label: countLabel(spark.count, 'Spark'),
                      active: spark.sparked,
                      onTap: onSpark == null
                          ? null
                          : () => onSpark!(!spark.sparked),
                    ),
                    _Action(
                      icon: Icons.mode_comment_outlined,
                      label: countLabel(post.commentCount, 'Comment'),
                      onTap: onComment,
                    ),
                    _Action(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ForwardPage.sharePost(post.id),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (footer != null) footer!,
            ],
          ),
        ],
      ),
    );
  }

  /// Follows or unfollows the author. Every card by them updates at once; if
  /// the server refuses, they all go back and the reason is shown.
  Future<void> _toggleFollow(
    BuildContext context,
    WidgetRef ref,
    bool following,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(socialActionsProvider)
        .setFollowing(post.author.id, !following);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Asks before deleting, then deletes.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'Delete this post?',
          style: AppTextStyles.fieldInput.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text("This can't be undone.", style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: AppTextStyles.linkText),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: AppTextStyles.linkText),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await ref.read(postDeleteProvider.notifier).delete(post.id);
      if (done) onDeleted?.call();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
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
  const _Avatar({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = avatarImage(post.author.profilePic);
    return GestureDetector(
      key: ValueKey('post-author-avatar-${post.author.id}'),
      onTap: onTap,
      child: Container(
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
      ),
    );
  }
}

/// "Spark", "1 Spark", "12 Sparks": the action's name after its count.
String countLabel(int count, String noun) => switch (count) {
  0 => noun,
  1 => '1 $noun',
  _ => '$count ${noun}s',
};

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
    final color = active ? AppColors.sparkAmber : AppColors.textDim;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // A roomy tap target, not just the icon.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.fieldInput.copyWith(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A post's pictures: one large, or several you swipe through. With more than
/// one, the edge of the next picture shows, a "2/4" counter sits on the
/// picture and dots run underneath, so it is obvious there is more to see.
/// Tap to look closer.
class PostImages extends StatefulWidget {
  const PostImages({super.key, required this.urls});

  final List<String> urls;

  /// How much of the row one picture takes: the rest is the next one
  /// peeking in, the cue that the row scrolls.
  static const viewportFraction = 0.88;

  @override
  State<PostImages> createState() => _PostImagesState();
}

class _PostImagesState extends State<PostImages> {
  late final PageController _pages = PageController(
    viewportFraction: PostImages.viewportFraction,
  );
  int _index = 0;

  List<String> get urls => widget.urls;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ImageViewer(urls: urls, initial: index),
      ),
    );
  }

  Widget _image(int i) {
    return CachedNetworkImage(
      imageUrl: urls[i],
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => Container(color: AppColors.paperRaised),
      errorWidget: (_, __, ___) => Container(
        color: AppColors.paperRaised,
        child: Icon(Icons.broken_image_outlined, color: AppColors.textDim),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: GestureDetector(onTap: () => _open(0), child: _image(0)),
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            children: [
              PageView.builder(
                key: const ValueKey('post-images'),
                controller: _pages,
                padEnds: false,
                itemCount: urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => Padding(
                  // A small gap, so the next picture reads as a separate one.
                  padding: EdgeInsets.only(right: i == urls.length - 1 ? 0 : 6),
                  child: GestureDetector(
                    onTap: () => _open(i),
                    child: _image(i),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_index + 1}/${urls.length}',
                      style: AppTextStyles.smallDim.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          key: const ValueKey('post-image-dots'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < urls.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _index ? AppColors.primary : AppColors.lineSoft,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The pictures full screen, to swipe through and zoom, with "2 of 4" on top
/// when there are several.
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.urls, required this.initial});

  final List<String> urls;
  final int initial;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.urls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: count > 1 ? Text('${_index + 1} of $count') : null,
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: count,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(child: CachedNetworkImage(imageUrl: widget.urls[i])),
        ),
      ),
    );
  }
}

/// A post's text: at most [maxLines] lines, then "See more". Tapping that
/// opens the rest in place.
class _PostBody extends StatefulWidget {
  const _PostBody({required this.text, this.showAll = false});

  static const maxLines = 5;

  final String text;
  final bool showAll;

  @override
  State<_PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends State<_PostBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.fieldInput;
    if (widget.showAll) return Text(widget.text, style: style);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: Directionality.of(context),
          maxLines: _PostBody.maxLines,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final tooLong = painter.didExceedMaxLines;
        painter.dispose();
        if (!tooLong) return Text(widget.text, style: style);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _open ? null : _PostBody.maxLines,
              overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Text(
                  _open ? 'See less' : 'See more',
                  style: AppTextStyles.smallDim.copyWith(
                    color: AppColors.primaryPale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
