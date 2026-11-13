import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/moment.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/presentation/view/video_trim_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/providers/moment_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/video_trim_providers.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/chat_file_picking.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/video_thumbnails.dart';

/// A video moment can be up to this long.
const maxMomentVideo = Duration(seconds: 60);

/// The most a caption can say.
const momentCaptionMax = 200;

/// Opens the screen to make a moment. True once it has been posted.
Future<bool> openMomentComposer(BuildContext context) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const MomentComposerPage(),
      ),
    ) ??
    false;

class MomentComposerPage extends ConsumerStatefulWidget {
  const MomentComposerPage({super.key});

  @override
  ConsumerState<MomentComposerPage> createState() => _MomentComposerPageState();
}

class _MomentComposerPageState extends ConsumerState<MomentComposerPage> {
  final _caption = TextEditingController();

  // What was chosen: a photo (shrunk) or a video (a file, maybe trimmed).
  Uint8List? _photo;
  PickedChatFile? _video;
  Uint8List? _thumbnail;
  // A trimmed copy is ours to delete once posted.
  bool _videoIsCopy = false;

  MomentAudience _audience = MomentAudience.friends;
  bool _allowSave = true;

  /// 0: the caption; 1: privacy (who sees it, and whether it can be saved).
  int _tab = 0;
  Set<String> _excluded = {};

  bool _busy = false;
  double? _progress;

  bool get _chosen => _photo != null || _video != null;

  @override
  void dispose() {
    _caption.dispose();
    _dropVideoCopy();
    super.dispose();
  }

  void _dropVideoCopy() {
    final video = _video;
    if (video != null && _videoIsCopy) File(video.path).delete().ignore();
    _videoIsCopy = false;
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.rust),
      );
  }

  // ----------------------------------------------------------- choosing ---

  Future<void> _fromCamera() async {
    try {
      final photo = await takeShrunkPhoto(maxSide: 1280, quality: 75);
      if (photo != null) await _usePhoto(photo);
    } catch (error) {
      _tell(humanError(error, fallback: "Couldn't open the camera."));
    }
  }

  Future<void> _fromGallery() async {
    try {
      final pick = await pickFromGallery(photos: true);
      if (pick == null) return;
      if (pick.photos.isNotEmpty) {
        await _usePhoto(pick.photos.first);
      } else if (pick.videos.isNotEmpty) {
        await _useVideo(pick.videos.first);
      }
    } catch (error) {
      _tell(humanError(error, fallback: "Couldn't open that."));
    }
  }

  Future<void> _usePhoto(Uint8List photo) async {
    final thumb = await _smallPreview(photo);
    if (!mounted) return;
    _dropVideoCopy();
    setState(() {
      _photo = photo;
      _video = null;
      _thumbnail = thumb;
    });
  }

  /// A JPEG of at most 48 KB, which travels with the moment.
  Future<Uint8List> _smallPreview(Uint8List photo) async {
    Uint8List? best;
    for (final (side, quality) in const [(320, 60), (240, 40), (160, 35)]) {
      best = await shrinkImage(photo, maxSide: side, quality: quality);
      if (best.length <= maxVideoThumbnailBytes) return best;
    }
    return best!;
  }

  Future<void> _useVideo(XFile picked) async {
    final trimmer = ref.read(videoTrimServiceProvider);
    if (!trimmer.supported) {
      _tell('Video moments need an Android phone for now. Try a photo.');
      return;
    }
    try {
      final file = checkChatFile(
        PickedChatFile(
          path: picked.path,
          name: picked.name,
          size: await picked.length(),
          kind: ChatFileKind.video,
        ),
      );
      if (!mounted) return;
      // Up to 60 seconds: a longer video is cut down here.
      final chosen = await chooseVideoPart(
        context,
        file,
        maxLength: maxMomentVideo,
        title: 'Choose up to 60 seconds',
      );
      if (chosen == null || !mounted) return;
      final isCopy = chosen.path != file.path;
      final checked = checkChatFile(chosen);
      final thumb = await makeVideoThumbnail(checked.path);
      if (thumb == null) {
        if (isCopy) File(checked.path).delete().ignore();
        _tell("Couldn't use that video.");
        return;
      }
      if (!mounted) return;
      _dropVideoCopy();
      setState(() {
        _video = checked;
        _videoIsCopy = isCopy;
        _photo = null;
        _thumbnail = thumb;
      });
    } on ChatFilePickException catch (e) {
      _tell(e.message);
    } catch (error) {
      _tell(humanError(error, fallback: "Couldn't use that video."));
    }
  }

  Future<void> _chooseExcluded() async {
    final chosen = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(builder: (_) => _ExcludePage(initial: _excluded)),
    );
    if (chosen != null && mounted) setState(() => _excluded = chosen);
  }

  // ------------------------------------------------------------ posting ---

  Future<void> _post() async {
    if (!_chosen || _busy) return;
    final thumb = _thumbnail!;
    final service = ref.read(momentServiceProvider);
    final audience = _audience;
    final exclude = audience == MomentAudience.except
        ? _excluded.toList()
        : const <String>[];
    final caption = _caption.text;
    setState(() {
      _busy = true;
      _progress = _video != null ? 0 : null;
    });
    try {
      if (_photo != null) {
        await service.postPhoto(
          photo: _photo!,
          thumbnail: thumb,
          audience: audience,
          excludeIds: exclude,
          caption: caption,
          allowSave: _allowSave,
        );
      } else {
        final video = _video!;
        final files = ref.read(chatFileServiceProvider);
        final contentType =
            chatFileContentType(video.name, ChatFileKind.video) ?? 'video/mp4';
        final clientId = 'moment-${DateTime.now().microsecondsSinceEpoch}';
        final upload = await service.startVideo(
          clientId: clientId,
          contentType: contentType,
          size: video.size,
          durationMs: video.durationMs ?? 0,
          thumbnail: thumb,
        );
        if (!upload.uploaded) {
          await files.upload(
            clientId: clientId,
            path: video.path,
            uploadPath: upload.uploadPath!,
            contentType: contentType,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
          await files.complete(upload.id);
        }
        await service.postVideo(
          mediaId: upload.id,
          thumbnail: thumb,
          audience: audience,
          excludeIds: exclude,
          caption: caption,
          allowSave: _allowSave,
        );
      }
      ref.invalidate(myMomentsProvider);
      final me = ref.read(currentAccountIdProvider);
      if (me != null) {
        unawaited(ref.read(momentRingsProvider.notifier).refresh([me]));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      _tell(humanError(error, fallback: "Couldn't post that moment."));
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  // -------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paperAlt,
          foregroundColor: AppColors.text,
          title: Text('NEW MOMENT', style: AppTextStyles.eyebrow),
          leading: IconButton(
            key: const ValueKey('composer-close'),
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _media(),
              if (_chosen) ...[
                const SizedBox(height: 16),
                _tabs(),
                const SizedBox(height: 12),
                if (_tab == 0) ...[
                  TextField(
                    key: const ValueKey('moment-caption-field'),
                    controller: _caption,
                    enabled: !_busy,
                    maxLength: momentCaptionMax,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTextStyles.body.copyWith(color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: 'Add a caption…',
                      hintStyle: AppTextStyles.smallDim,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.lineSoft),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Text('WHO CAN SEE IT', style: AppTextStyles.eyebrow),
                  const SizedBox(height: 8),
                  _audienceChoice(
                    MomentAudience.everyone,
                    Icons.public,
                    'Everyone on Serafim',
                    'Anyone can see it and reply.',
                  ),
                  _audienceChoice(
                    MomentAudience.friends,
                    Icons.group_outlined,
                    'Friends',
                    'Only your friends.',
                  ),
                  _audienceChoice(
                    MomentAudience.except,
                    Icons.person_off_outlined,
                    'Friends, except…',
                    _excluded.isEmpty
                        ? 'Choose friends who won’t see it.'
                        : '${_excluded.length} '
                              '${_excluded.length == 1 ? 'friend' : 'friends'}'
                              ' won’t see it.',
                  ),
                  if (_audience == MomentAudience.except)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('choose-excluded'),
                        onPressed: _busy ? null : _chooseExcluded,
                        child: const Text('Choose who to leave out'),
                      ),
                    ),
                  SettingsSwitchRow(
                    key: const ValueKey('allow-save'),
                    title: 'Let people save it',
                    subtitle: _allowSave
                        ? 'Others see a Save button.'
                        : 'No Save button. They can still screenshot it.',
                    value: _allowSave,
                    onChanged: _busy
                        ? null
                        : (on) => setState(() => _allowSave = on),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'It disappears after 24 hours.',
                  style: AppTextStyles.smallDim,
                ),
                const SizedBox(height: 16),
                if (_progress != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(value: _progress),
                  ),
                SerafimButton(
                  label: _busy ? 'POSTING…' : 'POST MOMENT',
                  onPressed: _busy ? null : _post,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget tab(int index, String label, Key key) {
      final on = _tab == index;
      return GestureDetector(
        key: key,
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.paperRaised : Colors.transparent,
            border: Border.all(
              color: on ? AppColors.primary : AppColors.lineSoft,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.fieldLabel.copyWith(
              color: on ? AppColors.primaryPale : AppColors.textDim,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(0, 'DETAILS', const ValueKey('moment-tab-details')),
        const SizedBox(width: 8),
        tab(1, 'PRIVACY', const ValueKey('moment-tab-privacy')),
      ],
    );
  }

  Widget _media() {
    if (!_chosen) {
      return Column(
        children: [
          const SizedBox(height: 24),
          Text(
            'Share a photo or a video of up to 60 seconds. It stays for 24 '
            'hours.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _source(
                  Icons.photo_camera_outlined,
                  'Camera',
                  _fromCamera,
                  const ValueKey('moment-camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _source(
                  Icons.photo_library_outlined,
                  'Gallery',
                  _fromGallery,
                  const ValueKey('moment-gallery'),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _photo ?? _thumbnail!,
              key: const ValueKey('moment-preview'),
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        ),
        if (_video != null)
          const Icon(
            Icons.play_circle_outline,
            color: Colors.white70,
            size: 64,
          ),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton.filled(
            key: const ValueKey('moment-change-media'),
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
            icon: const Icon(Icons.swap_horiz, color: Colors.white),
            tooltip: 'Choose another',
            onPressed: _busy
                ? null
                : () {
                    _dropVideoCopy();
                    setState(() {
                      _photo = null;
                      _video = null;
                      _thumbnail = null;
                    });
                  },
          ),
        ),
      ],
    );
  }

  Widget _source(IconData icon, String label, VoidCallback onTap, Key key) =>
      InkWell(
        key: key,
        onTap: onTap,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: AppColors.primaryPale),
              const SizedBox(height: 8),
              Text(label, style: AppTextStyles.body),
            ],
          ),
        ),
      );

  Widget _audienceChoice(
    MomentAudience value,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final selected = _audience == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('audience-${value.name}'),
        onTap: _busy ? null : () => setState(() => _audience = value),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.lineSoft,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.primary : AppColors.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    Text(subtitle, style: AppTextStyles.smallDim),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick the friends who won't see a moment.
class _ExcludePage extends ConsumerStatefulWidget {
  const _ExcludePage({required this.initial});

  final Set<String> initial;

  @override
  ConsumerState<_ExcludePage> createState() => _ExcludePageState();
}

class _ExcludePageState extends ConsumerState<_ExcludePage> {
  late final Set<String> _chosen = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsViewProvider).friends;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paperAlt,
        foregroundColor: AppColors.text,
        title: Text('LEAVE OUT', style: AppTextStyles.eyebrow),
        actions: [
          TextButton(
            key: const ValueKey('exclude-done'),
            onPressed: () => Navigator.of(context).pop(_chosen),
            child: const Text('Done'),
          ),
        ],
      ),
      body: friends.isEmpty
          ? Center(
              child: Text(
                'You have no friends to leave out yet.',
                style: AppTextStyles.smallDim,
              ),
            )
          : ListView(
              children: [
                for (final f in friends)
                  CheckboxListTile(
                    key: ValueKey('exclude-${f.id}'),
                    value: _chosen.contains(f.id),
                    onChanged: (on) => setState(
                      () =>
                          on == true ? _chosen.add(f.id) : _chosen.remove(f.id),
                    ),
                    secondary: AvatarThumb(
                      size: 38,
                      imageProvider:
                          f.profilePic == null || f.profilePic!.isEmpty
                          ? null
                          : NetworkImage(f.profilePic!),
                    ),
                    title: Text(f.displayName, style: AppTextStyles.body),
                    subtitle: Text(
                      '@${f.username}',
                      style: AppTextStyles.smallDim,
                    ),
                  ),
              ],
            ),
    );
  }
}
