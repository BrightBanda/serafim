import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/data/services/attachment_download_service.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/presentation/view/chat_background_page.dart';
import 'package:serafim/src/presentation/view/forward_page.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/providers/typing_providers.dart';
import 'package:serafim/src/utils/chat/reply_controller.dart';
import 'package:serafim/src/utils/chat/typing_bubble.dart';
import 'package:serafim/src/utils/chat/typing_broadcaster.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/text_edit_dialog.dart';
import 'package:serafim/src/presentation/view/image_preview_page.dart';
import 'package:serafim/src/presentation/view/draw_together_page.dart';
import 'package:serafim/src/presentation/view/scribble_page.dart';
import 'package:serafim/src/presentation/view/widgets/shared_post_card.dart';
import 'package:serafim/src/providers/draw_together_providers.dart';
import 'package:serafim/src/providers/wallpaper_providers.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/chat/message_actions.dart';
import 'package:serafim/src/utils/chat/swipe_to_reply.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
import 'package:serafim/src/utils/chat/link_preview_card.dart';
import 'package:serafim/src/providers/sticker_providers.dart';
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:serafim/src/utils/stickers/sticker_message.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/stickers/sticker_picker.dart';
import 'package:serafim/src/utils/stickers/collection_sheets.dart';
import 'package:serafim/src/utils/chat/chat_file_view.dart';
import 'package:serafim/src/utils/chat_file_picking.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/providers/chat_file_providers.dart';
import 'package:serafim/src/presentation/view/video_player_page.dart';
import 'package:serafim/src/presentation/view/chat_media_page.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/sticker_collection.dart';
import 'package:serafim/src/presentation/view/group_info_page.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/providers/voice_providers.dart';
import 'package:serafim/src/utils/voice/voice_note_view.dart';
import 'package:serafim/src/utils/voice/voice_recorder_controls.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.contactName,
    required this.recipientId,
    this.username,
    this.profilePic,
    this.isGroup = false,
    this.onBack,
    this.groupId,
  });

  /// Set for a group chat ([recipientId] is then the group id too).
  final String? groupId;

  final String contactName;
  final String recipientId;
  final String? username;
  final String? profilePic;
  final bool isGroup;
  final VoidCallback? onBack;

  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

/// Converts the database message status into the status expected by
/// [ChatBubble].
ChatMessageStatus _mapStatus(MessageStatus status) {
  switch (status) {
    case MessageStatus.sending:
      return ChatMessageStatus.sending;

    case MessageStatus.sent:
      return ChatMessageStatus.sent;

    case MessageStatus.delivered:
      return ChatMessageStatus.delivered;

    case MessageStatus.read:
      return ChatMessageStatus.read;

    case MessageStatus.failed:
      return ChatMessageStatus.failed;
  }
}

/// Orders messages newest first. The list is anchored to the bottom, so the
/// newest message is index 0 and older ones continue upwards.
///
/// The timestamp is the primary key and the local Isar ID the deterministic
/// tie-breaker, so we do not depend on the order the query returns.
List<LocalMessage> _sortMessagesNewestFirst(List<LocalMessage> messages) {
  final sorted = [...messages];
  sorted.sort((a, b) {
    final byTime = b.timestamp.compareTo(a.timestamp);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  });
  return sorted;
}

List<List<LocalMessage>> groupImagesForDisplay(List<LocalMessage> newestFirst) {
  final groups = <List<LocalMessage>>[];
  var index = 0;
  while (index < newestFirst.length) {
    final first = newestFirst[index];
    final group = <LocalMessage>[first];
    if (_isGridImage(first)) {
      var previous = first;
      var next = index + 1;
      while (next < newestFirst.length &&
          _canJoinImageGroup(previous, newestFirst[next])) {
        previous = newestFirst[next++];
        group.add(previous);
      }
      index = next;
    } else {
      index++;
    }
    groups.add(group);
  }
  return groups;
}

bool _isGridImage(LocalMessage message) =>
    message.type == MessageType.image &&
    !message.isDeleted &&
    message.localMediaPath != null;

bool _canJoinImageGroup(LocalMessage newer, LocalMessage older) {
  if (!_isGridImage(older) ||
      newer.senderId != older.senderId ||
      newer.groupId != older.groupId) {
    return false;
  }
  final delta = newer.timestamp
      .difference(older.timestamp)
      .inMicroseconds
      .abs();
  return delta <= const Duration(seconds: 8).inMicroseconds;
}

/// Formats a DateTime as HH:mm without relying on String.substring().
String _formatMessageTime(BuildContext context, DateTime timestamp) {
  final localTime = timestamp.toLocal();

  final timeOfDay = TimeOfDay.fromDateTime(localTime);

  return timeOfDay.format(context);
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();

  /// Tells the other side "typing…", sparingly (see [TypingBroadcaster]).
  late final TypingBroadcaster _typing = TypingBroadcaster(
    send: (typing) => ref
        .read(chatViewModelProvider.notifier)
        .sendTyping(
          recipientId: widget.recipientId,
          groupId: widget.groupId,
          typing: typing,
        ),
  );
  final ScrollController _scrollController = ScrollController();

  /// A photo is being prepared and sent.
  bool _attaching = false;

  /// Whether older messages exist beyond the window (the last load came back
  /// full). Updated whenever messages arrive.
  bool _hasMoreHistory = false;

  /// Message ids in list order (newest first), for jumping to a quoted message.
  List<String> _orderedIds = const [];

  /// Rough height of one message plus its gap, to estimate where an old message
  /// is before it has been built.
  static const _estimatedItemExtent = 92.0;

  String? _pendingReveal;

  /// Briefly tinted after jumping to it (search, "Show in chat", a quote).
  String? _highlightId;
  Timer? _highlightTimer;

  // Searching this chat: the matches, newest first, and which one is shown.
  bool _searching = false;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<String> _hits = const [];
  int _hit = 0;

  /// The message being replied to, while composing.
  late final ReplyController _reply = ReplyController(focusNode: _inputFocus);

  /// The sticker panel is open in place of the keyboard.
  bool _stickersOpen = false;
  final FocusNode _inputFocus = FocusNode();

  /// One key per message so a quote can scroll to its original.
  final Map<String, GlobalKey> _itemKeys = {};

  late final ActiveRoomNotifier _activeRoom;

  // Kept from initState: providers can't be read during dispose.
  late final VoiceRecorderController _recorder;
  late final VoicePlayerController _player;
  String? _registeredRoom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_loadOlderNearTop);
    _messageController.addListener(
      () => _typing.textChanged(_messageController.text),
    );
    _activeRoom = ref.read(activeRoomProvider.notifier);
    _recorder = ref.read(voiceRecorderProvider.notifier);
    _player = ref.read(voicePlayerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Tell alerts this conversation is on screen...
      _registeredRoom = _roomId;
      _activeRoom.set(_registeredRoom);
      // ...and opening it counts as reading what's already in it.
      _markRead();
    });
  }

  void _markRead() {
    if (!mounted) return;
    ref.read(chatViewModelProvider.notifier).markRoomRead(_roomId);
  }

  /// Today's upload allowance, as last fetched (when the attach sheet
  /// opened). Only used to warn early: the server has the final say.
  ChatFileQuota? _quota;

  Future<ChatFileQuota?> _loadQuota() async {
    try {
      final quota = await ref.read(chatFileServiceProvider).quota();
      if (mounted) _quota = quota;
      return quota;
    } catch (_) {
      return null; // Offline or old server: the upload itself will tell.
    }
  }

  String _sizeLimitText(ChatFileQuota? quota) {
    final perFile =
        'Up to ${formatFileSize(quota?.maxFile ?? maxChatFileBytes)}';
    if (quota == null) return perFile;
    return '$perFile · ${formatFileSize(quota.remaining)} left today';
  }

  /// The paperclip: a photo, a video or an audio file. Photos can't go to
  /// groups yet (the server relays them to one person only); videos and
  /// audio go through storage, so they can.
  Future<void> _handleAttach() async {
    if (ref.read(currentUserProvider) == null || _attaching) return;
    final photosBlocked = widget.groupId != null;
    final quota = _loadQuota();

    Widget option(
      BuildContext ctx,
      IconData icon,
      String title,
      String subtitle,
      String value, {
      bool enabled = true,
    }) => ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? AppColors.text : AppColors.lineSoft),
      title: Text(title, style: AppTextStyles.body),
      subtitle: Text(subtitle, style: AppTextStyles.smallDim),
      onTap: () => Navigator.pop(ctx, value),
    );

    final choice = await showSettledSheet<String>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
              ctx,
              Icons.photo_library_outlined,
              'Photo',
              photosBlocked
                  ? "Photos can't be shared in groups yet"
                  : 'From your gallery or camera',
              'photo',
              enabled: !photosBlocked,
            ),
            FutureBuilder<ChatFileQuota?>(
              future: quota,
              builder: (_, snap) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  option(
                    ctx,
                    Icons.movie_outlined,
                    'Video',
                    _sizeLimitText(snap.data),
                    'video',
                  ),
                  option(
                    ctx,
                    Icons.audiotrack_outlined,
                    'Audio file',
                    'MP3, M4A, WAV… ${_sizeLimitText(snap.data).toLowerCase()}',
                    'audio',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'photo':
        await _attachPhotos();
      case 'video':
        await _attachFile(ChatFileKind.video);
      case 'audio':
        await _attachFile(ChatFileKind.audio);
    }
  }

  Future<void> _attachFile(ChatFileKind kind) async {
    final PickedChatFile? file;
    try {
      file = await pickChatFile(kind);
    } on ChatFilePickException catch (e) {
      _toast(e.message, error: true);
      return;
    } catch (error) {
      _toast(
        humanError(error, fallback: "Couldn't open that file."),
        error: true,
      );
      return;
    }
    if (file == null || !mounted) return;
    await _sendFile(file);
  }

  /// Sends a video or audio file. Only copying it into the chat holds the
  /// composer up; the upload shows its progress in the bubble.
  Future<void> _sendFile(PickedChatFile file) async {
    if (_attaching) return;
    final quota = _quota;
    if (quota != null && file.size > quota.remaining) {
      final resets = MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(quota.resetsAt.toLocal()));
      _toast(
        quota.remaining == 0
            ? "You've used today's ${formatFileSize(quota.limit)} for videos, "
                  'audio and voice messages. It resets at $resets.'
            : 'That file is ${formatFileSize(file.size)}, but you have '
                  '${formatFileSize(quota.remaining)} left today. It resets '
                  'at $resets.',
        error: true,
      );
      return;
    }
    // Stale after this send; fetched again when the sheet next opens.
    _quota = null;
    setState(() => _attaching = true);
    try {
      await ref
          .read(chatViewModelProvider.notifier)
          .sendFile(
            roomId: _roomId,
            recipientId: widget.recipientId,
            groupId: widget.groupId,
            file: file,
            replyToId: _reply.value?.messageId,
            onError: _mediaSendFailed,
          );
      _reply.clear();
      _scheduleScrollToBottom();
    } catch (error) {
      _mediaSendFailed(error);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  void _mediaSendFailed(Object error) {
    if (!mounted) return;
    _toast(humanError(error, fallback: "Couldn't send that."), error: true);
  }

  Future<void> _downloadFile(LocalMessage message) async {
    final ok = await ref
        .read(chatViewModelProvider.notifier)
        .downloadFile(message.messageId);
    if (!ok && mounted) {
      _toast(
        "Couldn't download that. Check your connection and try again.",
        error: true,
      );
    }
  }

  Future<void> _attachPhotos() async {
    if (ref.read(currentUserProvider) == null || _attaching) return;
    final quality = ref.read(settingsProvider).imageQuality;
    try {
      final photos = await pickShrunkImages(
        context,
        maxSide: quality.maxSide,
        quality: quality.jpegQuality,
        // From here until the message is saved, show a spinner.
        onPicked: () {
          if (mounted) setState(() => _attaching = true);
        },
      );
      if (photos == null || !mounted) return;

      setState(() => _attaching = false);
      final toSend = photos.length > 1
          ? await previewImages(context, photos)
          : [
              if (await previewImage(
                    context,
                    photos.single,
                    maxSide: quality.maxSide,
                    quality: quality.jpegQuality,
                  )
                  case final edited?)
                edited,
            ];
      if (toSend == null || !mounted) return;
      setState(() => _attaching = true);

      for (var index = 0; index < toSend.length; index++) {
        await ref
            .read(chatViewModelProvider.notifier)
            .sendMessage(
              roomId: _roomId,
              recipientId: widget.recipientId,
              groupId: widget.groupId,
              imageBytes: toSend[index],
              replyToId: index == 0 ? _reply.value?.messageId : null,
            );
      }
      _reply.clear();
      _scheduleScrollToBottom();
    } catch (error) {
      _toast(
        humanError(error, fallback: "Couldn't send that photo."),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  /// The pencil: a scribble to send, or a canvas to draw on together.
  Future<void> _handlePencil() async {
    if (ref.read(currentUserProvider) == null || _attaching) return;
    final choice = await showSettledSheet<String>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('pencil-scribble'),
              leading: const Icon(Icons.draw_outlined),
              title: Text('Scribble', style: AppTextStyles.body),
              subtitle: Text(
                'Draw a quick note and send it',
                style: AppTextStyles.smallDim,
              ),
              onTap: () => Navigator.pop(ctx, 'scribble'),
            ),
            ListTile(
              key: const ValueKey('pencil-together'),
              leading: const Icon(Icons.people_alt_outlined),
              title: Text('Draw together', style: AppTextStyles.body),
              subtitle: Text(
                'Draw on the same canvas, live',
                style: AppTextStyles.smallDim,
              ),
              onTap: () => Navigator.pop(ctx, 'together'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'together') {
      await _startDrawTogether();
    } else if (choice == 'scribble') {
      await _handleScribble();
    }
  }

  Future<void> _startDrawTogether() async {
    final session = ref.read(drawTogetherProvider.notifier);
    if (session.busy) {
      // Already drawing with someone: go back to it.
      await openDrawTogether(Navigator.of(context));
      return;
    }
    if (!session.invite(widget.recipientId)) {
      _toast("Couldn't start. Check your connection.", error: true);
      return;
    }
    await openDrawTogether(Navigator.of(context));
  }

  /// A hand-drawn note: draw it, then it goes out like a picture.
  Future<void> _handleScribble() async {
    if (ref.read(currentUserProvider) == null || _attaching) return;
    final png = await scribble(context);
    if (png == null || !mounted) return;
    setState(() => _attaching = true);
    try {
      await ref
          .read(chatViewModelProvider.notifier)
          .sendMessage(
            roomId: _roomId,
            recipientId: widget.recipientId,
            groupId: widget.groupId,
            imageBytes: png,
            replyToId: _reply.value?.messageId,
          );
      _reply.clear();
      _scheduleScrollToBottom();
    } catch (error) {
      _toast(
        humanError(error, fallback: "Couldn't send that scribble."),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  @override
  void dispose() {
    final room = _registeredRoom;
    if (room != null) {
      // Not during the unmount itself: that would rebuild listeners while the
      // tree is locked.
      final notifier = _activeRoom;
      Future.microtask(() => notifier.clear(room));
    }
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the chat ends any recording and voice note playing in it (not
    // during the unmount itself, which can't change providers).
    final recorder = _recorder;
    final player = _player;
    Future.microtask(() {
      recorder.cancel();
      player.stop();
    });
    _messageController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _highlightTimer?.cancel();
    _scrollController.dispose();
    _typing.dispose();
    _reply.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  String? get _currentUserId {
    return ref.read(currentUserProvider)?.id;
  }

  String get _roomId {
    final gid = widget.groupId;
    if (gid != null) return groupRoomId(gid);
    final userId = _currentUserId;

    if (userId == null) {
      return widget.recipientId;
    }

    return ChatViewModel.buildRoomId(userId, widget.recipientId);
  }

  /// Opens the other person's profile. It shows straight away from the copy
  /// saved on the phone, then refreshes. (Its Message button is hidden: you are
  /// already in the conversation.)
  void _openProfile() {
    final gid = widget.groupId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => gid != null
            ? GroupInfoPage(groupId: gid)
            : UserProfilePage(userId: widget.recipientId, fromChat: true),
      ),
    );
  }

  /// Who sent [senderId]'s messages, as shown in this chat.
  /// Whether this friend's halo is lit ("free to chat").
  bool _friendHaloLit() {
    final friend = ref.watch(knownPersonProvider(widget.recipientId));
    return friend != null && ref.watch(haloLitProvider(haloKey(friend)));
  }

  String _nameOf(String senderId) {
    final gid = widget.groupId;
    if (gid == null) return widget.contactName;
    return ref.read(groupMemberNamesProvider(gid))[senderId] ??
        ref.read(knownPersonProvider(senderId))?.displayName ??
        'Member';
  }

  bool _rulesShown = false;

  /// Shows a group's rules the first time you open it after joining, and
  /// again whenever an admin changes them.
  void _maybeShowRules(GroupSummary group) {
    if (_rulesShown) return;
    if (!shouldShowRules(group, ref.read(rulesSeenProvider))) return;
    _rulesShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final String? rules;
      try {
        rules = (await ref.read(groupDetailProvider(group.id).future)).rules;
      } catch (_) {
        _rulesShown = false; // Try again next time.
        return;
      }
      if (!mounted || rules == null || rules.isEmpty) return;
      await showGroupRules(context, groupName: group.name, rules: rules);
      ref
          .read(rulesSeenProvider.notifier)
          .acknowledge(group.id, group.rulesUpdatedAt!);
    });
  }

  void _toast(String message, {bool error = false}) {
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

  /// Exports a picture, video or audio file to where the person keeps such
  /// things: the gallery for pictures and videos (Downloads on desktop), a
  /// place they choose for audio.
  Future<void> _saveToDevice(LocalMessage message, String senderLabel) async {
    final path = message.localMediaPath;
    if (path == null) return;
    final downloads = ref.read(attachmentDownloadServiceProvider);
    try {
      final String? where;
      switch (message.type) {
        case MessageType.video:
          _toast('Saving video…');
          where = await downloads.saveVideo(
            path,
            senderLabel: senderLabel,
            sentAt: message.timestamp,
          );
        case MessageType.audioFile:
          where = await downloads.saveAudio(
            path,
            fileName: message.fileName ?? path.split('/').last,
          );
        default:
          _toast('Saving image…');
          where = await downloads.saveImage(
            path,
            senderLabel: senderLabel,
            sentAt: message.timestamp,
          );
      }
      if (where != null) _toast(where);
    } on AttachmentSaveException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not save that.', error: true);
    }
  }

  /// Asks which collection to save to, then saves. [prepare] gets the item
  /// ready (for a file: reads it through once to name it by its contents).
  Future<void> _saveToCollection(
    Future<PendingCollectionItem> Function() prepare,
  ) async {
    final PendingCollectionItem pending;
    try {
      pending = await prepare();
    } catch (error) {
      _toast(humanError(error, fallback: "Couldn't read that."), error: true);
      return;
    }
    if (!mounted) return;
    final result = await showSaveToCollectionSheet(context, ref, pending);
    if (result != null && mounted) _toast(result);
  }

  Future<void> _saveStickerToCollection(String stickerId) => _saveToCollection(
    () async => PendingCollectionItem.sticker(
      stickerId,
      name: stickerById(stickerId)?.name,
    ),
  );

  /// Saves a sticker, GIF, video or audio file from a message.
  Future<void> _saveMessageToCollection(LocalMessage message) async {
    if (message.type == MessageType.sticker) {
      return _saveStickerToCollection(message.textContent ?? '');
    }
    final path = message.localMediaPath;
    if (path == null) return;
    final kind = switch (message.type) {
      MessageType.video => StickerCollectionItemKind.video,
      MessageType.audioFile => StickerCollectionItemKind.audio,
      _ => StickerCollectionItemKind.gif,
    };
    return _saveToCollection(
      () => ref
          .read(stickerCollectionsProvider.notifier)
          .prepareFile(path, kind, name: message.fileName),
    );
  }

  Future<void> _showMessageActions(
    LocalMessage message, {
    required bool isOutgoing,
    required String senderLabel,
  }) async {
    if (message.isDeleted) return;

    // A sticker's or shared post's "text" is its id, not something to copy
    // or edit.
    final text =
        message.type == MessageType.sticker || message.type == MessageType.post
        ? ''
        : message.textContent ?? '';
    final isImage =
        message.type == MessageType.image && message.localMediaPath != null;
    final isGif =
        isImage && message.localMediaPath!.toLowerCase().endsWith('.gif');
    final isSticker = message.type == MessageType.sticker;
    final isFile = isChatFile(message.type);
    final isConfirmed =
        message.status != MessageStatus.sending &&
        message.status != MessageStatus.failed;

    final actions = availableMessageActions(
      isOutgoing: isOutgoing,
      isDeleted: message.isDeleted,
      hasText: text.isNotEmpty,
      isImage: isImage,
      isGif: isGif,
      isSticker: isSticker,
      isFile: isFile,
      fileOnDevice: message.localMediaPath != null,
      isConfirmed: isConfirmed,
    );
    if (actions.isEmpty) return;

    final action = await showSettledSheet<String>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (ctx) {
        Widget tile(IconData icon, String label, String value) => ListTile(
          leading: Icon(icon, size: 20, color: AppColors.text),
          title: Text(
            label,
            style: AppTextStyles.body.copyWith(color: AppColors.text),
          ),
          onTap: () => Navigator.pop(ctx, value),
        );

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in actions)
                switch (a) {
                  MessageAction.copy => tile(Icons.copy, 'Copy text', 'copy'),
                  MessageAction.download => tile(
                    Icons.download_outlined,
                    switch (message.type) {
                      MessageType.video => 'Save video',
                      MessageType.audioFile => 'Save audio',
                      _ => isGif ? 'Download GIF' : 'Download image',
                    },
                    'download',
                  ),
                  MessageAction.edit => tile(
                    Icons.edit_outlined,
                    'Edit',
                    'edit',
                  ),
                  MessageAction.reply => tile(Icons.reply, 'Reply', 'reply'),
                  MessageAction.forward => tile(
                    Icons.forward,
                    'Forward',
                    'forward',
                  ),
                  MessageAction.save => tile(
                    Icons.bookmark_add,
                    'Save to collection',
                    'save',
                  ),
                  MessageAction.delete => tile(
                    Icons.delete_outline,
                    isConfirmed ? 'Delete for everyone' : 'Delete',
                    'delete',
                  ),
                },
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        _toast('Copied');
      case 'download':
        await _saveToDevice(message, senderLabel);
      case 'edit':
        await _editMessage(message);
      case 'reply':
        _startReply(message);
      case 'forward':
        await _forwardMessage(message);
      case 'save':
        await _saveMessageToCollection(message);
      case 'delete':
        await _deleteFlow(
          message,
          isOutgoing: isOutgoing,
          isConfirmed: isConfirmed,
        );
    }
  }

  /// Opens the picker for the chats this message can be forwarded to.
  Future<void> _forwardMessage(LocalMessage message) async {
    final navigator = Navigator.of(context);
    await navigator.push<int>(
      MaterialPageRoute<int>(builder: (_) => ForwardPage(messages: [message])),
    );
  }

  /// Edits one of our messages. The dialog stays open until the edit has
  /// been sent, and shows why if it could not be.
  Future<void> _editMessage(LocalMessage message) async {
    final original = message.textContent ?? '';
    await showTextEditDialog(
      context,
      title: 'Edit message',
      initial: original,
      maxLines: 5,
      maxLength: 4000,
      validate: (text) =>
          text.trim().isEmpty ? 'A message cannot be empty.' : null,
      onSave: (text) async {
        if (text.trim() == original) return null; // Nothing changed.
        return ref
            .read(chatViewModelProvider.notifier)
            .editMessage(message.messageId, text);
      },
    );
  }

  /// Asks how to delete: for me, or (own sent messages) for everyone.
  Future<void> _deleteFlow(
    LocalMessage message, {
    required bool isOutgoing,
    required bool isConfirmed,
  }) async {
    final options = deleteOptionsFor(
      isOutgoing: isOutgoing,
      isDeleted: message.isDeleted,
      isConfirmed: isConfirmed,
    );
    final isImage = message.type == MessageType.image;
    final what = isImage ? 'image' : 'message';

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text(
          'Delete $what?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          options.forEveryone
              ? '"Delete for me" removes it from this device only. "Delete for '
                    'everyone" removes it for everyone in the conversation and '
                    "can't be undone."
              : isOutgoing && !isConfirmed
              ? 'This $what was never delivered. It will be removed from this '
                    'device.'
              : widget.groupId != null
              ? 'It will be removed from this device. Others in the group '
                    'keep their copy.'
              : 'It will be removed from this device. ${widget.contactName} '
                    'keeps their copy.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'me'),
            child: Text(options.forEveryone ? 'Delete for me' : 'Delete'),
          ),
          if (options.forEveryone)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'everyone'),
              child: const Text('Delete for everyone'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final vm = ref.read(chatViewModelProvider.notifier);
    if (choice == 'everyone') {
      final error = await vm.deleteMessage(message.messageId);
      if (error != null) _toast(error, error: true);
    } else if (isOutgoing && !isConfirmed) {
      // Never reached the server: remove it outright.
      await vm.deleteMessage(message.messageId);
    } else {
      await vm.deleteForMe(message.messageId);
    }
    if (_reply.value?.messageId == message.messageId) _reply.clear();
  }

  /// A preview card for the first link in a text message, if any.
  Widget? _linkPreviewFor(LocalMessage message, bool outgoing) {
    if (message.isDeleted) return null;
    final uri = firstLink(message.textContent ?? '');
    if (uri == null) return null;
    return LinkPreviewCard(uri: uri, outgoing: outgoing);
  }

  // ---- replying ----

  String _snippetOf(LocalMessage m) {
    if (m.isDeleted) return 'Message deleted';
    if (m.type == MessageType.sticker) return '🙂 Sticker';
    if (m.type == MessageType.audio) return '🎤 Voice message';
    if (m.type == MessageType.post) return '📝 Post';
    if (m.type == MessageType.video) return '🎬 Video';
    if (m.type == MessageType.audioFile) return '🎵 ${m.fileName ?? 'Audio'}';
    final text = (m.textContent ?? '').trim();
    if (m.type == MessageType.image) {
      return text.isEmpty ? '📷 Photo' : '📷 $text';
    }
    return text;
  }

  void _startReply(LocalMessage message) {
    if (!_reply.start(message)) {
      _toast(
        message.isDeleted
            ? "You can't reply to a deleted message."
            : 'Wait until the message has been sent to reply to it.',
      );
      return;
    }
    // The sticker panel and the keyboard are never up together.
    if (_stickersOpen) setState(() => _stickersOpen = false);
  }

  ReplyQuoteData? _quoteFor(
    LocalMessage message,
    Map<String, LocalMessage> byId,
    String? myId,
  ) {
    final targetId = message.replyToId;
    if (targetId == null) return null;

    final original = byId[targetId];
    if (original == null) {
      return const ReplyQuoteData(
        author: 'Original message',
        snippet: 'No longer available',
        available: false,
      );
    }
    return ReplyQuoteData(
      author: original.senderId == myId ? 'You' : _nameOf(original.senderId),
      snippet: _snippetOf(original),
      available: !original.isDeleted,
      onTap: () => _scrollToMessage(targetId),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounded mid-recording: pause and keep it (hands-free), never lose
    // it. The user resumes or sends when they come back.
    if (state != AppLifecycleState.resumed) {
      ref.read(voiceRecorderProvider.notifier).interrupt();
    }
  }

  void _sendVoice(RecordedVoice voice) {
    ref
        .read(chatViewModelProvider.notifier)
        .sendVoice(
          roomId: _roomId,
          recipientId: widget.recipientId,
          groupId: widget.groupId,
          path: voice.path,
          durationMs: voice.durationMs,
          waveform: voice.waveform,
          replyToId: _reply.value?.messageId,
          onError: _mediaSendFailed,
        );
    _reply.clear();
    _scheduleScrollToBottom();
  }

  void _toggleStickers() {
    setState(() => _stickersOpen = !_stickersOpen);
    if (_stickersOpen) {
      _inputFocus.unfocus();
    } else {
      _inputFocus.requestFocus();
    }
  }

  void _sendSticker(String stickerId) {
    final me = _currentUserId;
    if (me == null) return;
    ref
        .read(chatViewModelProvider.notifier)
        .sendSticker(
          roomId: _roomId,
          recipientId: widget.recipientId,
          groupId: widget.groupId,
          stickerId: stickerId,
          replyToId: _reply.value?.messageId,
        );
    ref.read(recentStickersProvider.notifier).usedSticker(stickerId);
    _reply.clear();
    _scheduleScrollToBottom();
  }

  /// Asks before sending a saved video or audio file from the picker: unlike
  /// a sticker, one stray tap could spend a lot of data and of today's
  /// allowance.
  Future<bool> _confirmSendFile(StickerCollectionItem item, int size) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        shape: const RoundedRectangleBorder(),
        title: Text(
          'Send ${item.isVideo ? 'video' : 'audio'}?',
          style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: Text(
          '“${collectionItemLabel(item)}” · ${formatFileSize(size)}',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Something tapped in the sticker panel: a sticker or GIF goes at once
  /// (and into the recents); a saved video or audio file after a check.
  Future<void> _sendCollectionItem(StickerCollectionItem item) async {
    if (item.isSticker) {
      _sendSticker(item.stickerId!);
      return;
    }
    final path = await ref
        .read(stickerCollectionsProvider.notifier)
        .pathOf(item);
    final file = path == null ? null : File(path);
    if (file == null || !await file.exists()) {
      if (mounted) {
        _toast('That file is no longer on this phone.', error: true);
      }
      return;
    }
    if (!mounted) return;

    if (item.isGif) {
      // A GIF travels like a picture: relayed to one person, so not to
      // groups, and only up to the relay's size.
      if (widget.groupId != null) {
        _toast("GIFs can't be shared in groups yet.");
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxRawInsertBytes) {
        _toast('That GIF is too big to send.', error: true);
        return;
      }
      await ref
          .read(chatViewModelProvider.notifier)
          .sendMessage(
            roomId: _roomId,
            recipientId: widget.recipientId,
            groupId: null,
            imageBytes: bytes,
            replyToId: _reply.value?.messageId,
          );
      ref.read(recentStickersProvider.notifier).used(item);
      _reply.clear();
      _scheduleScrollToBottom();
      return;
    }

    final kind = item.isVideo ? ChatFileKind.video : ChatFileKind.audio;
    final size = await file.length();
    if (!mounted || !await _confirmSendFile(item, size) || !mounted) return;
    try {
      await _sendFile(
        checkChatFile(
          PickedChatFile(
            path: path!,
            name: item.name ?? collectionItemLabel(item),
            size: size,
            kind: kind,
          ),
        ),
      );
    } on ChatFilePickException catch (e) {
      _toast(e.message, error: true);
    }
  }

  /// A GIF, sticker or image inserted from the keyboard (Gboard etc.). Sent
  /// as an image attachment; GIFs and transparent stickers are kept as they
  /// are so they still animate / stay see-through.
  Future<void> _handleInserted(
    KeyboardInsertedContent content,
    String? attachDisabledReason,
  ) async {
    if (attachDisabledReason != null) {
      _toast(attachDisabledReason);
      return;
    }
    final bytes = content.data;
    if (bytes == null || bytes.isEmpty) {
      _toast("Couldn't add that from the keyboard.", error: true);
      return;
    }
    if (_attaching) return;
    setState(() => _attaching = true);
    try {
      final prepared = await prepareInsertedImage(
        bytes,
        content.mimeType,
        quality: ref.read(settingsProvider).imageQuality,
      );
      if (prepared == null) {
        _toast('That is too large to send.', error: true);
        return;
      }
      if (!mounted) return;
      await ref
          .read(chatViewModelProvider.notifier)
          .sendMessage(
            roomId: _roomId,
            recipientId: widget.recipientId,
            imageBytes: prepared,
            replyToId: _reply.value?.messageId,
          );
      _reply.clear();
      _scheduleScrollToBottom();
    } catch (error) {
      _toast(humanError(error, fallback: "Couldn't send that."), error: true);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  void _handleSend() {
    final content = _messageController.text.trim();

    if (content.isEmpty) {
      return;
    }

    final currentUser = ref.read(currentUserProvider);

    if (currentUser == null) {
      return;
    }

    ref
        .read(chatViewModelProvider.notifier)
        .sendMessage(
          roomId: _roomId,
          recipientId: widget.recipientId,
          groupId: widget.groupId,
          content: content,
          replyToId: _reply.value?.messageId,
        );

    _messageController.clear();
    _reply.clear();

    // The message is written to Isar before the socket send,
    // so the stream will update and the scroll will happen.
    _scheduleScrollToBottom();
  }

  /// The list is anchored to the bottom, so "the bottom" is scroll offset 0.
  void _scheduleScrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  bool get _nearBottom =>
      !_scrollController.hasClients || _scrollController.position.pixels < 240;

  /// Near the top (the oldest loaded message), load the next page of history.
  void _loadOlderNearTop() {
    if (!_hasMoreHistory || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _hasMoreHistory =
          false; // One request per page; the next arrival re-arms it.
      ref.read(messageWindowProvider(_roomId).notifier).loadMore();
    }
  }

  /// Scrolls to a message, first loading older history if it is beyond the
  /// window. Used when you tap a reply's quote.
  Future<void> _scrollToMessage(String messageId) async {
    final isar = ref.read(isarServiceProvider);
    final target = await isar.getMessageById(messageId);
    if (!mounted) return;
    if (target == null || target.isHiddenForMe) {
      _toast('That message is no longer on this device.');
      return;
    }
    final needed = await isar.countMessagesAtOrAfter(_roomId, target.timestamp);
    if (!mounted) return;
    ref.read(messageWindowProvider(_roomId).notifier).ensureAtLeast(needed);
    _pendingReveal = messageId;
    _tryReveal(attempts: 8);
  }

  void _flash(String messageId) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  Future<void> _openMedia() async {
    final messageId = await openChatMedia(
      context,
      roomId: _roomId,
      title: 'Media & links',
      nameOf: (id) => id == _currentUserId ? 'You' : _nameOf(id),
    );
    if (messageId != null && mounted) await _scrollToMessage(messageId);
  }

  void _openSearch() => setState(() {
    _searching = true;
    _stickersOpen = false;
  });

  void _closeSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searching = false;
      _searchController.clear();
      _hits = const [];
      _hit = 0;
    });
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _runSearch(text),
    );
  }

  Future<void> _runSearch(String text) async {
    final found = await ref.read(isarServiceProvider).searchRoom(_roomId, text);
    // Typing went on while this ran: a newer search will answer.
    if (!mounted || text != _searchController.text) return;
    setState(() {
      _hits = [for (final m in found) m.messageId];
      _hit = 0;
    });
    if (_hits.isNotEmpty) await _scrollToMessage(_hits.first);
  }

  /// [older] moves to the next older match; otherwise the next newer one.
  void _stepSearch({required bool older}) {
    if (_hits.isEmpty) return;
    final next = (_hit + (older ? 1 : -1)).clamp(0, _hits.length - 1);
    if (next == _hit) return;
    setState(() => _hit = next);
    _scrollToMessage(_hits[next]);
  }

  /// Brings [_pendingReveal] into view. A long list only builds what is on
  /// screen, so if the message has not been built yet, jump to roughly where
  /// it is and try again once the frame has built.
  void _tryReveal({required int attempts}) {
    final id = _pendingReveal;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingReveal != id || !_scrollController.hasClients) {
        return;
      }

      final built = _itemKeys[id]?.currentContext;
      if (built != null && built.mounted) {
        _pendingReveal = null;
        Scrollable.ensureVisible(
          built,
          alignment: 0.3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        _flash(id);
        return;
      }

      final index = _orderedIds.indexOf(id);
      if (attempts <= 0) {
        _pendingReveal = null;
        if (index < 0) _toast("Couldn't jump to that message.");
        return;
      }
      if (index >= 0) {
        final position = _scrollController.position;
        _scrollController.jumpTo(
          (index * _estimatedItemExtent).clamp(0.0, position.maxScrollExtent),
        );
      }
      _tryReveal(attempts: attempts - 1);
    });
  }

  void _handleMessagesChanged(
    AsyncValue<List<LocalMessage>>? previous,
    AsyncValue<List<LocalMessage>> next,
  ) {
    final previousMessages = previous?.value;
    final currentMessages = next.value;

    if (currentMessages == null || next.isLoading) return;

    // A full window means there is probably more history above it. (The window
    // is read now, so it is the one this result was loaded for.)
    _hasMoreHistory =
        currentMessages.length >= ref.read(messageWindowProvider(_roomId));

    // The newest message changed: a message was sent or arrived. (Loading older
    // history changes the *oldest* end, and must not move the view.)
    final newest = currentMessages.isEmpty
        ? null
        : _sortMessagesNewestFirst(currentMessages).first;
    final previousNewest =
        (previousMessages == null || previousMessages.isEmpty)
        ? null
        : _sortMessagesNewestFirst(previousMessages).first;
    final isNew =
        newest != null &&
        previousNewest != null &&
        newest.messageId != previousNewest.messageId;
    if (isNew && (newest.senderId == _currentUserId || _nearBottom)) {
      _scheduleScrollToBottom();
    }

    // We're looking at this conversation, so anything incoming is read.
    final myId = _currentUserId;
    final hasUnread = currentMessages.any(
      (m) =>
          (widget.groupId != null
              ? m.senderId != myId
              : m.recipientId == myId) &&
          m.status != MessageStatus.read,
    );
    if (hasUnread) _markRead();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?.id;

    final gid = widget.groupId;
    final roomId = gid != null
        ? groupRoomId(gid)
        : currentUserId != null
        ? ChatViewModel.buildRoomId(currentUserId, widget.recipientId)
        : widget.recipientId;

    final messagesProvider = roomMessagesStreamProvider(roomId);

    // React to actual message additions instead of calling scroll
    // from inside the widget's build process.
    ref.listen<AsyncValue<List<LocalMessage>>>(
      messagesProvider,
      _handleMessagesChanged,
    );

    final messagesAsync = ref.watch(messagesProvider);

    // Attachments are friends-only. The button explains why it is off; the
    // server refuses them regardless.
    final friendsView = ref.watch(friendsViewProvider);
    final isFriend = ref.watch(friendIdsProvider).contains(widget.recipientId);
    // Groups: names for message labels, rules on first open, and whether
    // you are still a member.
    GroupSummary? group;
    var removedFromGroup = false;
    if (gid != null) {
      ref.watch(groupMemberNamesProvider(gid));
      group = ref.watch(myGroupProvider(gid));
      final groupsLoaded = ref.watch(myGroupsProvider).hasValue;
      removedFromGroup = groupsLoaded && group == null;
      if (group != null) _maybeShowRules(group);
    }

    // Pictures (photos, GIFs, scribbles) are relayed to one person, so not
    // to groups; in a 1:1 chat every attachment needs friendship.
    final String? notFriendsReason = gid != null || isFriend
        ? null
        : !friendsView.hasData && friendsView.isRefreshing
        ? 'Checking whether you are friends…'
        : 'Add ${widget.contactName} as a friend to share photos, videos '
              'and audio.';
    final photoDisabledReason = gid != null
        ? "Photos and GIFs can't be shared in groups yet."
        : notFriendsReason;

    return PopScope(
      canPop: !_stickersOpen && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searching) {
          _closeSearch();
        } else if (_stickersOpen) {
          setState(() => _stickersOpen = false);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,

        appBar: AppTopBar(
          onBack: widget.onBack ?? () => Navigator.of(context).pop(),
          titleFontSize: 15,
          trailing: ChatMenuButton(
            roomId: roomId,
            onMedia: _openMedia,
            onSearch: _openSearch,
          ),
          // Tapping the photo opens it full screen; the name opens the profile.
          titleWidget: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openProfile,
            child: Row(
              children: [
                TappableAvatar(
                  size: 30,
                  isGroup: widget.isGroup,
                  halo: !widget.isGroup && _friendHaloLit(),
                  heroTag: 'thread:${widget.recipientId}',
                  name: widget.contactName,
                  image:
                      (widget.profilePic != null &&
                          widget.profilePic!.isNotEmpty)
                      ? CachedNetworkImageProvider(widget.profilePic!)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    gid != null
                        ? '${group?.name ?? widget.contactName}'
                              '${group != null ? ' · ${group.memberCount} members' : ''}'
                        : widget.username ?? widget.contactName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // The wallpaper sits behind everything; bubbles and the input bar are
        // opaque, so it only shows in the gaps.
        body: Stack(
          children: [
            Positioned.fill(
              child: ChatWallpaperView(
                wallpaper: ref.watch(roomWallpaperProvider(roomId)),
              ),
            ),
            Column(
              children: [
                if (_searching)
                  _ChatSearchBar(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    hits: _hits.length,
                    current: _hit,
                    onOlder: () => _stepSearch(older: true),
                    onNewer: () => _stepSearch(older: false),
                    onClose: _closeSearch,
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: _StatusLine(),
                ),

                Expanded(
                  child: messagesAsync.when(
                    skipLoadingOnReload: true,
                    loading: () {
                      return Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    },

                    error: (error, stack) {
                      return Center(
                        child: Text(
                          humanError(
                            error,
                            fallback: "Couldn't load this conversation.",
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.rustPale),
                        ),
                      );
                    },

                    data: (messages) {
                      if (messages.isEmpty) {
                        return const _EmptyChat();
                      }

                      final orderedMessages = _sortMessagesNewestFirst(
                        messages,
                      );
                      _orderedIds = [
                        for (final m in orderedMessages) m.messageId,
                      ];
                      final byId = {
                        for (final m in orderedMessages) m.messageId: m,
                      };

                      // Replies whose original is older than the window.
                      final missing = <String>{
                        for (final m in orderedMessages)
                          if (m.replyToId != null &&
                              !byId.containsKey(m.replyToId))
                            m.replyToId!,
                      };
                      if (missing.isNotEmpty) {
                        final ids = (missing.toList()..sort()).join(',');
                        byId.addAll(
                          ref.watch(quotedMessagesProvider(ids)).value ??
                              const {},
                        );
                      }

                      // Who is typing here (never yourself): shown as the
                      // newest item, at the bottom of the conversation.
                      final typingNow = [
                        for (final id in ref.watch(
                          typingInRoomProvider(roomId),
                        ))
                          if (id != currentUserId) _nameOf(id),
                      ];
                      final typingRows = typingNow.isEmpty ? 0 : 1;
                      final displayGroups = groupImagesForDisplay(
                        orderedMessages,
                      );

                      return ListView.separated(
                        controller: _scrollController,
                        reverse: true,

                        padding: const EdgeInsets.all(14),

                        itemCount: displayGroups.length + typingRows,

                        separatorBuilder: (_, __) {
                          return const SizedBox(height: 10);
                        },

                        itemBuilder: (context, index) {
                          if (typingRows == 1 && index == 0) {
                            return TypingBubble(who: typingNow.join(', '));
                          }
                          final group = displayGroups[index - typingRows];
                          final message = group.first;

                          final isOutgoing =
                              currentUserId != null &&
                              message.senderId == currentUserId;

                          final time = _formatMessageTime(
                            context,
                            message.timestamp,
                          );

                          final senderLabel =
                              (isOutgoing
                                  ? 'You · $time'
                                  : '${_nameOf(message.senderId)} · $time') +
                              (message.editedAt != null && !message.isDeleted
                                  ? ' · edited'
                                  : '');
                          final who = isOutgoing
                              ? 'you'
                              : _nameOf(message.senderId);

                          final Widget bubble =
                              message.type == MessageType.sticker &&
                                  !message.isDeleted
                              ? StickerMessage(
                                  stickerId: message.textContent ?? '',
                                  label: senderLabel,
                                  outgoing: isOutgoing,
                                  status: isOutgoing
                                      ? _mapStatus(message.status)
                                      : null,
                                  onTap: () => _showMessageActions(
                                    message,
                                    isOutgoing: isOutgoing,
                                    senderLabel: who,
                                  ),
                                  onLongPress: () => _showMessageActions(
                                    message,
                                    isOutgoing: isOutgoing,
                                    senderLabel: who,
                                  ),
                                )
                              : ChatBubble(
                                  who: senderLabel,
                                  quote: _quoteFor(
                                    message,
                                    byId,
                                    currentUserId,
                                  ),
                                  // A shared post's text is its id: the card
                                  // below shows the post instead.
                                  message: message.type == MessageType.post
                                      ? ''
                                      : message.textContent ?? '',
                                  imagePath:
                                      message.type == MessageType.image &&
                                          group.length == 1
                                      ? message.localMediaPath
                                      : null,
                                  onTapImage:
                                      message.type == MessageType.image &&
                                          message.localMediaPath != null &&
                                          message.localMediaPath!
                                              .toLowerCase()
                                              .endsWith('.gif')
                                      ? () => _showMessageActions(
                                          message,
                                          isOutgoing: isOutgoing,
                                          senderLabel: who,
                                        )
                                      : null,
                                  imageAttachments: group.length > 1
                                      ? [
                                          for (final image in group.reversed)
                                            ChatImageAttachment(
                                              path: image.localMediaPath!,
                                              key: _itemKeys.putIfAbsent(
                                                image.messageId,
                                                GlobalKey.new,
                                              ),
                                              onLongPress: () =>
                                                  _showMessageActions(
                                                    image,
                                                    isOutgoing: isOutgoing,
                                                    senderLabel: who,
                                                  ),
                                              onSave: () =>
                                                  _saveToDevice(image, who),
                                              onDelete: () => _deleteFlow(
                                                image,
                                                isOutgoing: isOutgoing,
                                                isConfirmed:
                                                    image.status !=
                                                        MessageStatus.sending &&
                                                    image.status !=
                                                        MessageStatus.failed,
                                              ),
                                            ),
                                        ]
                                      : const [],
                                  side: isOutgoing
                                      ? ChatBubbleSide.outgoing
                                      : ChatBubbleSide.incoming,
                                  status: isOutgoing
                                      ? _mapStatus(message.status)
                                      : null,
                                  deleted: message.isDeleted,
                                  forwarded: message.forwarded,
                                  footer:
                                      message.type == MessageType.audio &&
                                          !message.isDeleted
                                      ? VoiceNoteView(
                                          messageId: message.messageId,
                                          outgoing: isOutgoing,
                                          path: message.localMediaPath,
                                          durationMs: message.durationMs ?? 0,
                                          waveform:
                                              message.waveform ?? const [],
                                          failed:
                                              message.status ==
                                              MessageStatus.failed,
                                          onRetry: () => ref
                                              .read(
                                                chatViewModelProvider.notifier,
                                              )
                                              .retryVoice(
                                                message.messageId,
                                                onError: _mediaSendFailed,
                                              ),
                                          onDownload: () => ref
                                              .read(
                                                chatViewModelProvider.notifier,
                                              )
                                              .downloadVoice(message.messageId),
                                        )
                                      : isChatFile(message.type) &&
                                            !message.isDeleted
                                      ? ChatFileView(
                                          message: message,
                                          outgoing: isOutgoing,
                                          onRetry: () => ref
                                              .read(
                                                chatViewModelProvider.notifier,
                                              )
                                              .retryFile(
                                                message.messageId,
                                                onError: _mediaSendFailed,
                                              ),
                                          onDownload: () =>
                                              _downloadFile(message),
                                          onOpenVideo: () => openChatVideo(
                                            context,
                                            path: message.localMediaPath!,
                                            title: message.fileName ?? 'Video',
                                          ),
                                        )
                                      : message.type == MessageType.post &&
                                            !message.isDeleted
                                      ? SharedPostCard(
                                          postId: message.textContent ?? '',
                                          outgoing: isOutgoing,
                                          onLongPress: () =>
                                              _showMessageActions(
                                                message,
                                                isOutgoing: isOutgoing,
                                                senderLabel: who,
                                              ),
                                        )
                                      : _linkPreviewFor(message, isOutgoing),
                                  onLongPress: () => _showMessageActions(
                                    message,
                                    isOutgoing: isOutgoing,
                                    senderLabel: who,
                                  ),
                                  onSaveImage: () =>
                                      _saveToDevice(message, who),
                                  onDeleteImage: () => _deleteFlow(
                                    message,
                                    isOutgoing: isOutgoing,
                                    isConfirmed:
                                        message.status !=
                                            MessageStatus.sending &&
                                        message.status != MessageStatus.failed,
                                  ),
                                );

                          return KeyedSubtree(
                            key: _itemKeys.putIfAbsent(
                              group.length > 1
                                  ? 'image-grid:${message.messageId}'
                                  : message.messageId,
                              GlobalKey.new,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              color:
                                  _highlightId != null &&
                                      group.any(
                                        (m) => m.messageId == _highlightId,
                                      )
                                  ? AppColors.primary.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              child: SwipeToReply(
                                enabled: !message.isDeleted,
                                onReply: () => _startReply(message),
                                child: bubble,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                if (widget.groupId == null)
                  DrawInviteBar(peerId: widget.recipientId),
                if (removedFromGroup)
                  const _NotInGroup()
                else
                  ValueListenableBuilder<LocalMessage?>(
                    valueListenable: _reply,
                    builder: (context, replyTarget, _) => ChatInputBar(
                      controller: _messageController,
                      focusNode: _inputFocus,
                      onSend: _handleSend,
                      onAttach: _handleAttach,
                      onScribble: _handlePencil,
                      attachDisabledReason: notFriendsReason,
                      scribbleDisabledReason: photoDisabledReason,
                      attachBusy: _attaching,
                      onStickers: _toggleStickers,
                      stickersOpen: _stickersOpen,
                      recordingStrip:
                          ref.watch(
                            voiceRecorderProvider.select((r) => r.active),
                          )
                          ? const RecordingStrip()
                          : null,
                      trailing: MicButton(
                        onRecorded: _sendVoice,
                        onTell: (m) => _toast(m),
                      ),
                      onContentInserted: (content) =>
                          _handleInserted(content, photoDisabledReason),
                      replyPreview: replyTarget == null
                          ? null
                          : (
                              author: replyTarget.senderId == currentUserId
                                  ? 'yourself'
                                  : _nameOf(replyTarget.senderId),
                              snippet: _snippetOf(replyTarget),
                              onCancel: _reply.clear,
                            ),
                    ),
                  ),
                if (_stickersOpen)
                  StickerPicker(
                    onSend: _sendCollectionItem,
                    onSave: (item) => _saveToCollection(
                      // Already in the app (a pack sticker, or a GIF from
                      // the recents): nothing to read.
                      () async => PendingCollectionItem(item),
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

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: AppColors.paper.withValues(alpha: 0.85),
        child: Text(
          'No messages yet. Say hi!',
          style: TextStyle(color: AppColors.textDim),
        ),
      ),
    );
  }
}

class _StatusLine extends ConsumerWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(chatViewModelProvider).isConnected;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // Translucent so the status stays readable on any background.
        color: AppColors.paper.withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: AppColors.lineSoft, width: 1)),
      ),
      child: Text(
        isConnected ? 'COMM-LINK ESTABLISHED' : 'COMM-LINK OFFLINE',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 9,
          color: isConnected ? AppColors.textDim : Colors.red.shade300,
        ),
      ),
    );
  }
}

/// The ⋮ menu in a chat's header. [onMedia] and [onSearch] add those
/// entries where the chat supports them.
class ChatMenuButton extends StatelessWidget {
  const ChatMenuButton({
    super.key,
    required this.roomId,
    this.onMedia,
    this.onSearch,
  });

  final String roomId;
  final VoidCallback? onMedia;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.text),
              const SizedBox(width: 10),
              Text(
                label,
                style: AppTextStyles.body.copyWith(color: AppColors.text),
              ),
            ],
          ),
        );

    return PopupMenuButton<String>(
      tooltip: 'Chat options',
      color: AppColors.paperAlt,
      shape: Border.all(color: AppColors.line, width: 1.5),
      icon: Icon(Icons.more_vert, size: 20, color: AppColors.text),
      onSelected: (value) => switch (value) {
        'search' => onSearch?.call(),
        'media' => onMedia?.call(),
        _ => openChatBackgroundPage(context, roomId: roomId),
      },
      itemBuilder: (_) => [
        if (onSearch != null) item('search', Icons.search, 'Search'),
        if (onMedia != null)
          item('media', Icons.perm_media_outlined, 'Media & links'),
        item('background', Icons.wallpaper_outlined, 'Chat background'),
      ],
    );
  }
}

/// Search box for the open chat, with the match count and older/newer
/// arrows.
class _ChatSearchBar extends StatelessWidget {
  const _ChatSearchBar({
    required this.controller,
    required this.onChanged,
    required this.hits,
    required this.current,
    required this.onOlder,
    required this.onNewer,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int hits;
  final int current;
  final VoidCallback onOlder;
  final VoidCallback onNewer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final typed = controller.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border(bottom: BorderSide(color: AppColors.line, width: 1.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: AppColors.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('chat-search-field'),
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onOlder(),
              style: AppTextStyles.body.copyWith(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Search this chat',
                hintStyle: AppTextStyles.smallDim,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (typed)
            Text(
              hits == 0 ? 'No results' : '${current + 1} of $hits',
              style: AppTextStyles.smallDim,
            ),
          IconButton(
            tooltip: 'Older',
            visualDensity: VisualDensity.compact,
            onPressed: current < hits - 1 ? onOlder : null,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: 'Newer',
            visualDensity: VisualDensity.compact,
            onPressed: current > 0 ? onNewer : null,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          IconButton(
            tooltip: 'Close search',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Replaces the composer in a group you are no longer in.
class _NotInGroup extends StatelessWidget {
  const _NotInGroup();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Text(
          "You're no longer a member of this group.",
          textAlign: TextAlign.center,
          style: AppTextStyles.smallDim,
        ),
      ),
    );
  }
}
