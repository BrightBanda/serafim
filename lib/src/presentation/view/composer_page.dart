import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Writes a post.
///
/// With a [circleId] it goes inside that Circle; without one, it goes on
/// your own profile.
class ComposerPage extends ConsumerStatefulWidget {
  const ComposerPage({super.key, this.circleId, this.circleName});

  final String? circleId;
  final String? circleName;

  @override
  ConsumerState<ComposerPage> createState() => _ComposerPageState();
}

class _ComposerPageState extends ConsumerState<ComposerPage> {
  /// The heading, like a forum thread.
  final _title = TextEditingController();
  final _controller = TextEditingController();
  bool _busy = false;

  /// What the busy state is for, so the button can say so: adding pictures
  /// (choosing and shrinking them, then uploading) or posting.
  String _working = 'POSTING…';
  String? _error;

  /// Pictures chosen so far, already shrunk to fit the 2 MB limit.
  final List<Uint8List> _images = [];

  @override
  void dispose() {
    _title.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// How many more pictures may be attached.
  ///
  /// Two limits apply at once: at most [PostLimits.imagesMax] on one post, and
  /// at most [PostLimits.dailyImagesMax] a day across all of them. The
  /// pictures already attached to this draft count towards the daily limit,
  /// because they go up with the post.
  int _roomFor(int remaining) {
    final perPost = PostLimits.imagesMax - _images.length;
    final perDay = remaining - _images.length;
    return perPost < perDay ? perPost : perDay;
  }

  Future<void> _addImages(int remaining) async {
    final room = _roomFor(remaining);
    if (room <= 0) return;
    setState(() => _error = null);
    try {
      final picker = ImagePicker();
      final picked = room == 1
          ? [await picker.pickImage(source: ImageSource.gallery)]
          : await picker.pickMultiImage(limit: room);
      final files = [
        for (final f in picked)
          if (f != null) f,
      ];
      if (files.isEmpty) return;
      setState(() {
        _busy = true;
        _working = 'ADDING IMAGES…';
      });
      var skipped = 0;
      for (final file in files.take(room)) {
        final small = await shrinkToLimit(
          await file.readAsBytes(),
          maxBytes: PostLimits.imageBytesMax,
        );
        if (small == null) {
          skipped++;
        } else {
          _images.add(small);
        }
      }
      if (files.length > room) skipped += files.length - room;
      if (skipped > 0 && mounted) {
        setState(
          () => _error =
              'Up to ${PostLimits.imagesMax} pictures, 2 MB each. '
              '$skipped could not be added.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _post() async {
    if (_busy) return;
    final title = _title.text.trim();
    final text = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Add a heading.');
      return;
    }
    setState(() {
      _busy = true;
      _working = _images.isEmpty ? 'POSTING…' : 'ADDING IMAGES…';
      _error = null;
    });
    try {
      final me = ref.read(currentAccountIdProvider);
      final storage = ref.read(avatarStorageServiceProvider);
      final urls = <String>[];
      if (me != null) {
        for (final bytes in _images) {
          urls.add(await storage.uploadPostImage(me, bytes));
        }
      }
      if (mounted) setState(() => _working = 'POSTING…');
      final posted = await ref
          .read(postComposerProvider.notifier)
          .post(
            title: title,
            content: text,
            circleId: widget.circleId,
            imageUrls: urls,
          );
      if (!mounted) return;
      if (posted == null) {
        // The controller keeps the failure; show it and stay on the page.
        final error = ref.read(postComposerProvider).error;
        setState(
          () => _error = humanError(error ?? 'That did not go through.'),
        );
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final circleName =
        widget.circleName ??
        ref.watch(circleDetailProvider(widget.circleId ?? '')).value?.name;
    final quota = ref.watch(postImageQuotaProvider);
    final remaining = quota.value?.remaining ?? PostLimits.dailyImagesMax;
    final used = quota.value?.used ?? 0;
    final limit = quota.value?.limit ?? PostLimits.dailyImagesMax;
    final outOfPictures = remaining <= 0;
    final full = _images.length >= PostLimits.imagesMax;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(title: 'NEW POST', onBack: _back),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
          children: [
            if (circleName != null && circleName.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  border: Border.all(color: AppColors.lineSoft, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: 15,
                      color: AppColors.primaryPale,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Posting in $circleName',
                        style: AppTextStyles.fieldInput,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: PostLimits.titleMax,
              style: AppTextStyles.fieldInput.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              cursorColor: AppColors.primaryPale,
              decoration: InputDecoration(
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                ),
                hintText: 'Heading',
                hintStyle: AppTextStyles.fieldInput.copyWith(
                  color: AppColors.textDim,
                ),
                counterStyle: AppTextStyles.smallDim,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 8,
              minLines: 5,
              maxLength: PostLimits.contentMax,
              style: AppTextStyles.fieldInput.copyWith(fontSize: 15),
              cursorColor: AppColors.primaryPale,
              decoration: InputDecoration(
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                ),
                hintText: 'Break the silence',
                hintStyle: AppTextStyles.fieldInput.copyWith(
                  color: AppColors.textDim,
                ),
                counterStyle: AppTextStyles.smallDim,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: _busy || outOfPictures || full
                      ? null
                      : () => _addImages(remaining),
                  child: Row(
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: outOfPictures
                            ? AppColors.textDim
                            : AppColors.primaryPale,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        outOfPictures
                            ? 'Daily picture limit reached'
                            : 'Add pictures (${_images.length}/${PostLimits.imagesMax})',
                        style: AppTextStyles.smallDim.copyWith(
                          color: outOfPictures
                              ? AppColors.rustPale
                              : AppColors.primaryPale,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Pictures today: $used/$limit', style: AppTextStyles.smallDim),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      Image.memory(
                        _images[i],
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _busy
                              ? null
                              : () => setState(() => _images.removeAt(i)),
                          child: Container(
                            color: Colors.black54,
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
              ),
            ],
            const SizedBox(height: 20),
            SerafimButton(
              label: _busy ? _working : 'POST',
              onPressed: _busy ? null : _post,
            ),
          ],
        ),
      ),
    );
  }
}
