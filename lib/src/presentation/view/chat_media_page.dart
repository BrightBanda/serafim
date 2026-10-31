import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/presentation/view/video_player_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_image_gallery.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/limited_gif.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/voice/voice_math.dart';

enum ChatMediaKind { image, video, audio, link }

/// One thing in a chat's media: a photo/GIF, video, voice note or audio
/// file, or one link (a message with two links gives two entries).
class ChatMediaEntry {
  const ChatMediaEntry(this.message, this.kind, {this.link});

  final LocalMessage message;
  final ChatMediaKind kind;
  final Uri? link;
}

/// Sorts [messages] (newest first) into media entries, newest first.
/// Pictures need to be on this device; videos and audio show either way
/// (they can be downloaded from here).
List<ChatMediaEntry> chatMediaEntries(List<LocalMessage> messages) => [
  for (final m in messages)
    if (!m.isDeleted && !m.isHiddenForMe)
      ...switch (m.type) {
        MessageType.image when m.localMediaPath != null => [
          ChatMediaEntry(m, ChatMediaKind.image),
        ],
        MessageType.video => [ChatMediaEntry(m, ChatMediaKind.video)],
        MessageType.audio ||
        MessageType.audioFile => [ChatMediaEntry(m, ChatMediaKind.audio)],
        MessageType.text => [
          for (final link in findLinks(m.textContent ?? ''))
            ChatMediaEntry(m, ChatMediaKind.link, link: link.uri),
        ],
        _ => const <ChatMediaEntry>[],
      },
];

final _roomMediaProvider = StreamProvider.autoDispose
    .family<List<ChatMediaEntry>, String>(
      (ref, roomId) => ref
          .watch(isarServiceProvider)
          .watchRoomMedia(roomId)
          .map(chatMediaEntries),
    );

/// Opens a chat's photos, videos, audio and links. Resolves to a message id
/// when the person picks "Show in chat".
Future<String?> openChatMedia(
  BuildContext context, {
  required String roomId,
  required String title,
  required String Function(String senderId) nameOf,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => ChatMediaPage(roomId: roomId, title: title, nameOf: nameOf),
  ),
);

class ChatMediaPage extends ConsumerWidget {
  const ChatMediaPage({
    super.key,
    required this.roomId,
    required this.title,
    required this.nameOf,
  });

  final String roomId;
  final String title;
  final String Function(String senderId) nameOf;

  static const tabs = ['All', 'Photos', 'Videos', 'Audio', 'Links'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(_roomMediaProvider(roomId));
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppTopBar(
          title: title.toUpperCase(),
          onBack: () => Navigator.of(context).pop(),
        ),
        body: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.lineSoft, width: 1.5),
                ),
              ),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textDim,
                indicatorColor: AppColors.primary,
                labelStyle: AppTextStyles.fieldLabel,
                tabs: [for (final t in tabs) Tab(text: t.toUpperCase())],
              ),
            ),
            Expanded(
              child: media.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => _Empty(humanError(e)),
                data: (all) {
                  List<ChatMediaEntry> of(ChatMediaKind k) => [
                    for (final e in all)
                      if (e.kind == k) e,
                  ];
                  final images = of(ChatMediaKind.image);
                  return TabBarView(
                    children: [
                      _MediaList(entries: all, images: images, nameOf: nameOf),
                      _ImageGrid(images: images),
                      _VideoGrid(videos: of(ChatMediaKind.video)),
                      _MediaList(
                        entries: of(ChatMediaKind.audio),
                        images: images,
                        nameOf: nameOf,
                        empty: 'No audio yet.',
                      ),
                      _MediaList(
                        entries: of(ChatMediaKind.link),
                        images: images,
                        nameOf: nameOf,
                        empty: 'No links yet.',
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Long-press on anything: jump to it in the chat.
Future<void> _offerShowInChat(BuildContext context, LocalMessage m) async {
  final go = await showSettledSheet<bool>(
    context: context,
    backgroundColor: AppColors.paperAlt,
    shape: const RoundedRectangleBorder(),
    builder: (ctx) => SafeArea(
      child: ListTile(
        leading: Icon(Icons.chat_bubble_outline, color: AppColors.text),
        title: Text('Show in chat', style: AppTextStyles.body),
        onTap: () => Navigator.pop(ctx, true),
      ),
    ),
  );
  if (go == true && context.mounted) Navigator.of(context).pop(m.messageId);
}

void _openImages(
  BuildContext context,
  List<ChatMediaEntry> images,
  LocalMessage m,
) {
  final index = images.indexWhere((e) => e.message.messageId == m.messageId);
  openChatImageGallery(context, [
    for (final e in images)
      (path: e.message.localMediaPath!, onSave: null, onDelete: null),
  ], initialIndex: index < 0 ? 0 : index);
}

/// Plays a video, or fetches it first.
Future<void> _openVideo(
  BuildContext context,
  WidgetRef ref,
  LocalMessage m,
) async {
  final path = m.localMediaPath;
  if (path != null) {
    await openChatVideo(context, path: path, title: m.fileName ?? 'Video');
    return;
  }
  final ok = await ref
      .read(chatViewModelProvider.notifier)
      .downloadFile(m.messageId);
  if (!ok && context.mounted) _toast(context, "Couldn't download that.");
}

/// Plays a voice note or audio file, fetching it first if needed.
Future<void> _playAudio(
  BuildContext context,
  WidgetRef ref,
  LocalMessage m,
) async {
  final path = m.localMediaPath;
  if (path != null) {
    await ref
        .read(voicePlayerProvider.notifier)
        .toggle(m.messageId, path, durationMs: m.durationMs);
    return;
  }
  final vm = ref.read(chatViewModelProvider.notifier);
  final ok = m.type == MessageType.audio
      ? await vm.downloadVoice(m.messageId)
      : await vm.downloadFile(m.messageId);
  if (!ok && context.mounted) _toast(context, "Couldn't download that.");
}

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: AppTextStyles.smallDim));
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});
  final List<ChatMediaEntry> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const _Empty('No photos yet.');
    final cache = (130 * MediaQuery.devicePixelRatioOf(context)).round();
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: images.length,
      itemBuilder: (_, i) {
        final m = images[i].message;
        return GestureDetector(
          onTap: () => _openImages(context, images, m),
          onLongPress: () => _offerShowInChat(context, m),
          child: isGifPath(m.localMediaPath!)
              ? LimitedGif(
                  path: m.localMediaPath!,
                  loops: 1,
                  fit: BoxFit.cover,
                  cacheWidth: cache,
                  showReplay: false,
                  errorBuilder: (_) => const _Missing(),
                )
              : Image.file(
                  File(m.localMediaPath!),
                  fit: BoxFit.cover,
                  cacheWidth: cache,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: AppColors.paperRaised,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _VideoGrid extends ConsumerWidget {
  const _VideoGrid({required this.videos});
  final List<ChatMediaEntry> videos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (videos.isEmpty) return const _Empty('No videos yet.');
    final transfers = ref.watch(fileTransfersProvider);
    final cache = (130 * MediaQuery.devicePixelRatioOf(context)).round();
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: videos.length,
      itemBuilder: (_, i) {
        final m = videos[i].message;
        final transfer = transfers[m.messageId];
        return GestureDetector(
          onTap: () => _openVideo(context, ref, m),
          onLongPress: () => _offerShowInChat(context, m),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (m.thumbnailPath case final thumb?)
                Image.file(
                  File(thumb),
                  fit: BoxFit.cover,
                  cacheWidth: cache,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF1E2230)),
                )
              else
                const ColoredBox(color: Color(0xFF1E2230)),
              Center(
                child: transfer != null
                    ? SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(
                          value: transfer.progress <= 0
                              ? null
                              : transfer.progress,
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        m.localMediaPath == null
                            ? Icons.download_rounded
                            : Icons.play_circle_outline,
                        color: Colors.white,
                        size: 30,
                      ),
              ),
              if (m.fileSize case final size?)
                Positioned(
                  left: 4,
                  bottom: 3,
                  child: Text(
                    formatFileSize(size),
                    style: AppTextStyles.fieldLabel.copyWith(
                      color: Colors.white,
                      fontSize: 8,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A list of entries of any kind: used for All, Audio and Links.
class _MediaList extends ConsumerWidget {
  const _MediaList({
    required this.entries,
    required this.images,
    required this.nameOf,
    this.empty = 'Nothing shared yet.',
  });

  final List<ChatMediaEntry> entries;
  final List<ChatMediaEntry> images;
  final String Function(String senderId) nameOf;
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return _Empty(empty);
    final playback = ref.watch(voicePlayerProvider);
    final transfers = ref.watch(fileTransfersProvider);
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.lineSoft),
      itemBuilder: (_, i) {
        final e = entries[i];
        final m = e.message;
        final when = formatChatListTime(context, m.timestamp);
        final who = nameOf(m.senderId);

        final Widget leading;
        final String title;
        final String detail;
        final VoidCallback onTap;
        switch (e.kind) {
          case ChatMediaKind.image:
            leading = _Thumb(
              child: isGifPath(m.localMediaPath!)
                  ? LimitedGif(
                      path: m.localMediaPath!,
                      loops: 1,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      showReplay: false,
                      errorBuilder: (_) => const _Missing(),
                    )
                  : Image.file(
                      File(m.localMediaPath!),
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, _, _) => const _Missing(),
                    ),
            );
            title = isGifPath(m.localMediaPath!) ? 'GIF' : 'Photo';
            detail = '$who · $when';
            onTap = () => _openImages(context, images, m);
          case ChatMediaKind.video:
            leading = _Thumb(
              child: m.thumbnailPath == null
                  ? const Icon(Icons.movie_outlined, color: Colors.white70)
                  : Image.file(
                      File(m.thumbnailPath!),
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.movie_outlined,
                        color: Colors.white70,
                      ),
                    ),
            );
            title = m.fileName ?? 'Video';
            detail = [
              who,
              when,
              if (m.fileSize case final s?) formatFileSize(s),
            ].join(' · ');
            onTap = () => _openVideo(context, ref, m);
          case ChatMediaKind.audio:
            final voice = m.type == MessageType.audio;
            final playing =
                playback.messageId == m.messageId && playback.playing;
            final busy = transfers.containsKey(m.messageId);
            leading = _Thumb(
              light: true,
              child: Icon(
                busy
                    ? Icons.downloading_rounded
                    : playing
                    ? Icons.pause_rounded
                    : m.localMediaPath == null
                    ? Icons.download_rounded
                    : voice
                    ? Icons.mic_none_rounded
                    : Icons.audiotrack_outlined,
                color: AppColors.text,
              ),
            );
            title = voice ? 'Voice message' : (m.fileName ?? 'Audio');
            detail = [
              who,
              when,
              if (m.durationMs case final ms? when ms > 0)
                formatVoiceDuration(Duration(milliseconds: ms)),
            ].join(' · ');
            onTap = () => _playAudio(context, ref, m);
          case ChatMediaKind.link:
            leading = _Thumb(
              light: true,
              child: Icon(Icons.link, color: AppColors.primary),
            );
            title = e.link!.host.replaceFirst(RegExp(r'^www\.'), '');
            detail = '${e.link} · $when';
            onTap = () => openLink(e.link!);
        }

        return ListTile(
          leading: leading,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(color: AppColors.text),
          ),
          subtitle: Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.smallDim,
          ),
          onTap: onTap,
          onLongPress: () => _offerShowInChat(context, m),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.child, this.light = false});
  final Widget child;
  final bool light;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    clipBehavior: Clip.hardEdge,
    decoration: BoxDecoration(
      color: light ? AppColors.paperRaised : const Color(0xFF1E2230),
      border: Border.all(color: AppColors.lineSoft, width: 1.5),
    ),
    child: Center(child: child),
  );
}

/// Shown for a picture that is no longer on this phone (cleared by "keep
/// messages for", or not included in a restored backup).
class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.broken_image_outlined, color: AppColors.textDim, size: 20);
}
