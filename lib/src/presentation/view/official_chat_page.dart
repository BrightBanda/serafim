import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:serafim/src/utils/media_picker/media_widgets.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/chat_file_picking.dart';
import 'package:serafim/src/providers/media_library_providers.dart';
import 'package:serafim/src/presentation/view/video_player_page.dart';
import 'package:serafim/src/presentation/view/media_gallery_page.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/utils/serafim_loader.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart'
    show ChatMenuButton;
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/wallpaper_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/presentation/view/post_update_page.dart';
import 'package:serafim/src/utils/chat/link_preview_card.dart';
import 'package:serafim/src/utils/update/update_card.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/official_badge.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The active-room id used while the official chat is on screen, so its
/// announcements don't also raise a banner.
const officialRoomId = 'serafim-official';

void openOfficialChat(BuildContext context) =>
    openOfficialChatWithNavigator(Navigator.of(context));

void openOfficialChatWithNavigator(NavigatorState navigator) {
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => const OfficialChatPage()),
  );
}

/// The official SERAFIM chat: announcements from the team, read-only for
/// everyone except administrators, who get a composer. Everything shown comes
/// from the server (and the copy of it saved on the phone).
class OfficialChatPage extends ConsumerStatefulWidget {
  const OfficialChatPage({super.key});

  @override
  ConsumerState<OfficialChatPage> createState() => _OfficialChatPageState();
}

class _OfficialChatPageState extends ConsumerState<OfficialChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final ActiveRoomNotifier _activeRoom;
  bool _posting = false;

  /// How far a video's upload has got, while one is uploading.
  double? _progress;

  @override
  void initState() {
    super.initState();
    _activeRoom = ref.read(activeRoomProvider.notifier);
    _scroll.addListener(_loadOlderNearTop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activeRoom.set(officialRoomId);
      ref.read(officialChatProvider.notifier).reload();
    });
  }

  @override
  void dispose() {
    // Not during the unmount itself: that would rebuild listeners while the
    // tree is locked.
    final notifier = _activeRoom;
    Future.microtask(() => notifier.clear(officialRoomId));
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _loadOlderNearTop() {
    // The list is reversed: the top is the far end.
    if (_scroll.position.extentAfter < 300) {
      ref.read(officialChatProvider.notifier).loadOlder();
    }
  }

  void _tell(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.rust : null,
        ),
      );
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    final error = await ref.read(officialChatProvider.notifier).post(text);
    if (!mounted) return;
    setState(() => _posting = false);
    if (error != null) {
      _tell(error);
    } else {
      _controller.clear();
    }
  }

  /// Administrators: chooses a video and announces it, with whatever is typed
  /// as its words.
  Future<void> _attachVideo() async {
    if (_posting) return;
    final file = await _chooseVideo();
    if (file == null || !mounted) return;
    setState(() {
      _posting = true;
      _progress = 0;
    });
    final error = await ref
        .read(officialChatProvider.notifier)
        .postVideo(
          file,
          content: _controller.text,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
    if (!mounted) return;
    setState(() {
      _posting = false;
      _progress = null;
    });
    if (error != null) {
      _tell(error);
    } else {
      _controller.clear();
    }
  }

  /// Inside the app where possible, so Android has no reason to close it.
  Future<PickedChatFile?> _chooseVideo() async {
    final library = ref.read(mediaLibraryProvider);
    var access = MediaAccess.unavailable;
    try {
      access = await library.access(MediaFilter.videos);
      if (access == MediaAccess.denied) {
        access = await library.request(MediaFilter.videos);
      }
    } catch (_) {}
    if (!mounted) return null;
    try {
      XFile? picked;
      if (access.canRead) {
        final result = await Navigator.of(context).push<Object>(
          MaterialPageRoute(
            builder: (_) => const MediaGalleryPage(
              filter: MediaFilter.videos,
              single: true,
            ),
          ),
        );
        if (result is List<DeviceMedia> && result.isNotEmpty) {
          final m = result.first;
          final file = await m.file();
          if (file == null) {
            _tell("That video isn't on your phone any more.");
            return null;
          }
          return checkChatFile(
            PickedChatFile(
              path: file.path,
              name: await m.name(),
              size: await file.length(),
              kind: ChatFileKind.video,
              durationMs: m.duration.inMilliseconds,
            ),
          );
        }
        if (result != browseFiles) return null;
        picked = (await browseMediaFiles(photos: false))?.videos.firstOrNull;
      } else {
        picked = (await pickFromGallery(photos: false))?.videos.firstOrNull;
      }
      if (picked == null) return null;
      return checkChatFile(
        PickedChatFile(
          path: picked.path,
          name: picked.name,
          size: await picked.length(),
          kind: ChatFileKind.video,
        ),
      );
    } on ChatFilePickException catch (e) {
      _tell(e.message);
      return null;
    } catch (e) {
      _tell(humanError(e, fallback: "Couldn't open that video."));
      return null;
    }
  }

  Future<void> _confirmDelete(Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Delete announcement?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          'It will be removed for everyone.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await ref.read(officialChatProvider.notifier).delete(a.id);
    if (error != null) _tell(error);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(officialChatProvider);
    final chat = async.value;

    // Looking at the chat counts as having read what is in it.
    final latest = chat?.latest;
    if (latest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(officialLastReadProvider.notifier)
              .markSeen(latest.createdAt);
        }
      });
    }

    Widget list;
    if (chat == null && async.hasError) {
      list = _Centered(
        text: humanError(async.error, fallback: "Couldn't load announcements."),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(officialChatProvider),
      );
    } else if (chat == null) {
      list = const Center(child: SerafimLoader());
    } else if (chat.announcements.isEmpty) {
      list = const _Centered(
        text:
            'No announcements yet.\nNews from the SERAFIM team will appear here.',
      );
    } else {
      final items = chat.announcements;
      list = ListView.separated(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.all(14),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final a = items[i];
          final update = a.update;
          if (update != null) {
            return Align(
              alignment: Alignment.centerLeft,
              child: UpdateCard(
                update: update,
                onLongPress: chat.canPost ? () => _confirmDelete(a) : null,
              ),
            );
          }
          return ChatBubble(
            who: 'SERAFIM · ${formatChatListTime(context, a.createdAt)}',
            message: a.caption,
            side: ChatBubbleSide.incoming,
            footer: a.video != null
                ? AnnouncementVideoCard(announcement: a)
                : switch (firstLink(a.content)) {
                    final uri? => LinkPreviewCard(uri: uri, outgoing: false),
                    null => null,
                  },
            onLongPress: chat.canPost ? () => _confirmDelete(a) : null,
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).pop(),
        titleWidget: Row(
          children: [
            const SerafimMark(size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'SERAFIM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const OfficialBadge(),
          ],
        ),
        trailing: const ChatMenuButton(roomId: officialRoomId),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ChatWallpaperView(
              wallpaper: ref.watch(roomWallpaperProvider(officialRoomId)),
            ),
          ),
          Column(
            children: [
              const _InfoStrip(),
              Expanded(child: list),
              if (_progress case final progress?)
                LinearProgressIndicator(
                  key: const ValueKey('announcement-upload-progress'),
                  value: progress,
                  minHeight: 3,
                  color: AppColors.primary,
                ),
              if (chat?.canPost ?? false) const _AnnounceUpdateBar(),
              if (chat?.canPost ?? false)
                ChatInputBar(
                  controller: _controller,
                  onAttach: _attachVideo,
                  attachBusy: _posting,
                  hintText: _progress != null
                      ? 'Uploading the video…'
                      : _posting
                      ? 'Posting…'
                      : 'Post an announcement to everyone…',
                  onSend: _posting ? null : _post,
                )
              else
                const _ReadOnlyFooter(),
            ],
          ),
        ],
      ),
    );
  }
}

/// An announcement's video: its picture, length and size. Tapping fetches it
/// the first time, then plays it; nothing is downloaded until then.
class AnnouncementVideoCard extends ConsumerStatefulWidget {
  const AnnouncementVideoCard({
    super.key,
    required this.announcement,
    this.play = _openVideo,
  });

  final Announcement announcement;

  /// Plays the file at a path. Replaced in tests.
  final void Function(BuildContext context, String path, String title) play;

  static void _openVideo(BuildContext context, String path, String title) =>
      unawaited(openChatVideo(context, path: path, title: title));

  @override
  ConsumerState<AnnouncementVideoCard> createState() =>
      _AnnouncementVideoCardState();
}

class _AnnouncementVideoCardState extends ConsumerState<AnnouncementVideoCard> {
  double? _progress;
  bool _fetching = false;

  late final Uint8List? _picture = _decode(
    widget.announcement.video?.thumbnail,
  );

  static Uint8List? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _open() async {
    if (_fetching) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _fetching = true;
      _progress = null;
    });
    try {
      final path = await ref
          .read(officialVideoStoreProvider)
          .fileFor(
            widget.announcement,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (mounted) {
        widget.play(context, path, widget.announcement.video!.name);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(humanError(e, fallback: "Couldn't load that video.")),
        ),
      );
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.announcement.video!;
    final picture = _picture;
    final length = formatMediaDuration(
      Duration(milliseconds: video.durationMs),
    );
    return GestureDetector(
      key: ValueKey('announcement-video-${widget.announcement.id}'),
      onTap: _open,
      child: SizedBox(
        width: 230,
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: picture == null
                  ? null
                  : Image.memory(
                      picture,
                      fit: BoxFit.cover,
                      cacheWidth: 460,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
            Center(
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: _fetching
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          key: const ValueKey('announcement-video-fetching'),
                          value: _progress,
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: Colors.black54,
                child: Text(
                  video.durationMs > 0
                      ? '$length · ${formatFileSize(video.size)}'
                      : formatFileSize(video.size),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border.all(color: AppColors.lineSoft, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_outlined, size: 16, color: AppColors.primaryPale),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Official news and announcements from the SERAFIM team.',
              style: AppTextStyles.smallDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyFooter extends StatelessWidget {
  const _ReadOnlyFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.paperRaised, AppColors.paperAlt],
        ),
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 13, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text(
              'Only SERAFIM can post in this chat',
              style: AppTextStyles.smallDim,
            ),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          color: AppColors.paper.withValues(alpha: 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!, style: AppTextStyles.linkText),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admins only: a way into "announce an update" above the composer.
class _AnnounceUpdateBar extends StatelessWidget {
  const _AnnounceUpdateBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.paperRaised,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PostUpdatePage()),
          ),
          icon: Icon(
            Icons.system_update_alt,
            size: 16,
            color: AppColors.primaryPale,
          ),
          label: Text('Announce an app update', style: AppTextStyles.linkText),
        ),
      ),
    );
  }
}
