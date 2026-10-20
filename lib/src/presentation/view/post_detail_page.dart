import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/presentation/view/circle_detail_page.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Opens a post's page. Used wherever a [PostCard] is shown.
Future<void> openPost(BuildContext context, String postId) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => PostDetailPage(postId: postId)));

/// Opens the Circle a post belongs to.
Future<void> openCircle(BuildContext context, String circleId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CircleDetailPage(circleId: circleId),
      ),
    );

/// One post with its comments and replies.
class PostDetailPage extends ConsumerStatefulWidget {
  const PostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<PostDetailPage> {
  final _controller = TextEditingController();
  bool _busy = false;

  /// The comment being replied to, if any.
  PostComment? _replyTo;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _back() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // A reply to a reply is attached to the top-level comment, so threads
      // stay one level deep.
      final parent = _replyTo == null
          ? null
          : (_replyTo!.parentId ?? _replyTo!.id);
      await ref
          .read(commentProvider.notifier)
          .comment(widget.postId, content: text, parentId: parent);
      ref.invalidate(postProvider(widget.postId));
      if (!mounted) return;
      _controller.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    final comments = ref.watch(postCommentsProvider(widget.postId));

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(title: 'POST', onBack: _back),
      body: post.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              humanError(e),
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (p) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                children: [
                  PostCard(
                    post: p,
                    onSpark: (on) => ref
                        .read(sparkProvider.notifier)
                        .togglePost(p.id, on: on),
                    onCircleTap: p.circle == null
                        ? null
                        : () => openCircle(context, p.circle!.id),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'COMMENTS',
                    style: AppTextStyles.eyebrow.copyWith(fontSize: 10),
                  ),
                  const SizedBox(height: 8),
                  ...comments.when(
                    loading: () => [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    error: (e, _) => [
                      Text(humanError(e), style: AppTextStyles.body),
                    ],
                    data: (list) => _thread(list, p),
                  ),
                ],
              ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  List<Widget> _thread(List<PostComment> all, Post post) {
    if (all.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No comments yet.', style: AppTextStyles.smallDim),
        ),
      ];
    }
    final me = ref.watch(currentAccountIdProvider);
    final top = [
      for (final c in all)
        if (!c.isReply) c,
    ];
    final replies = <String, List<PostComment>>{};
    for (final c in all) {
      if (c.parentId != null) (replies[c.parentId!] ??= []).add(c);
    }
    Widget tile(PostComment c, {required bool indent}) => _CommentTile(
      comment: c,
      indent: indent,
      canDelete: c.author.id == me || post.author.id == me,
      onReply: () => setState(() => _replyTo = c),
    );
    return [
      for (final c in top) ...[
        tile(c, indent: false),
        for (final r in replies[c.id] ?? const <PostComment>[])
          tile(r, indent: true),
      ],
    ];
  }

  Widget _composer() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border(top: BorderSide(color: AppColors.lineSoft, width: 1.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        8,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Replying to ${_replyTo!.author.displayName}',
                    style: AppTextStyles.smallDim,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _replyTo = null),
                  child: Icon(Icons.close, size: 15, color: AppColors.textDim),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: PostLimits.commentMax,
                  style: AppTextStyles.fieldInput,
                  cursorColor: AppColors.primaryPale,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Add a comment',
                    hintStyle: AppTextStyles.fieldInput.copyWith(
                      color: AppColors.textDim,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : _send,
                icon: Icon(Icons.send, size: 20, color: AppColors.primaryPale),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.comment,
    required this.indent,
    required this.canDelete,
    required this.onReply,
  });

  final PostComment comment;
  final bool indent;
  final bool canDelete;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = comment.sparked ? AppColors.primaryPale : AppColors.textDim;
    return Padding(
      padding: EdgeInsets.only(left: indent ? 28 : 0, bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(color: AppColors.lineSoft, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comment.author.displayName,
              style: AppTextStyles.fieldInput.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(comment.content, style: AppTextStyles.fieldInput),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ref
                      .read(sparkProvider.notifier)
                      .toggleComment(comment.id, on: !comment.sparked),
                  child: Row(
                    children: [
                      Icon(
                        comment.sparked ? Icons.bolt : Icons.bolt_outlined,
                        size: 18,
                        color: color,
                      ),
                      if (comment.sparkCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${comment.sparkCount}',
                          style: AppTextStyles.smallDim.copyWith(color: color),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: onReply,
                  child: Text('Reply', style: AppTextStyles.smallDim),
                ),
                const Spacer(),
                if (canDelete)
                  GestureDetector(
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref
                            .read(postServiceProvider)
                            .deleteComment(comment.id);
                        ref.invalidate(postCommentsProvider(comment.postId));
                        ref.invalidate(postProvider(comment.postId));
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(humanError(e))),
                        );
                      }
                    },
                    child: Icon(
                      Icons.delete_outline,
                      size: 15,
                      color: AppColors.rustPale,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
