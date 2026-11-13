import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/moment.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/moment_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:video_player/video_player.dart';

/// Opens [userId]'s moments full screen, from the first one you haven't seen.
/// For your own (pass your own id) it shows who looked and liked instead of a
/// reply box.
Future<void> openMoments(
  BuildContext context, {
  required String userId,
  required String name,
  ImageProvider? avatar,
}) => Navigator.of(context).push<void>(
  PageRouteBuilder(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) =>
        MomentViewerPage(userId: userId, name: name, avatar: avatar),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

/// How long a photo moment shows before the next one.
const photoMomentDuration = Duration(seconds: 5);

class MomentViewerPage extends ConsumerStatefulWidget {
  const MomentViewerPage({
    super.key,
    required this.userId,
    required this.name,
    this.avatar,
  });

  final String userId;
  final String name;
  final ImageProvider? avatar;

  @override
  ConsumerState<MomentViewerPage> createState() => _MomentViewerPageState();
}

class _MomentViewerPageState extends ConsumerState<MomentViewerPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: photoMomentDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _next();
        });
  final _progress = ValueNotifier<double>(0);
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  List<Moment> _moments = const [];
  int _index = 0;
  bool _loading = true;
  bool _failed = false;
  VideoPlayerController? _video;
  bool _videoFailed = false;
  bool _sending = false;

  /// Why the show is held: a finger down, the reply box, a sheet. It plays
  /// again when nothing holds it.
  final Set<Object> _holds = {};

  bool get _mine => ref.read(currentAccountIdProvider) == widget.userId;
  Moment? get _current => _moments.isEmpty ? null : _moments[_index];

  @override
  void initState() {
    super.initState();
    _clock.addListener(() => _progress.value = _clock.value);
    _replyFocus.addListener(() => _hold(_replyFocus, _replyFocus.hasFocus));
    unawaited(_load());
  }

  @override
  void dispose() {
    _clock.dispose();
    _progress.dispose();
    _video?.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final moments = await ref.read(userMomentsProvider(widget.userId).future);
      if (!mounted) return;
      if (moments.isEmpty) {
        _toast('Nothing to see here: the moment has ended.');
        Navigator.of(context).pop();
        return;
      }
      final firstUnseen = moments.indexWhere((m) => !m.seen);
      setState(() {
        _moments = moments;
        _loading = false;
      });
      _start(firstUnseen < 0 ? 0 : firstUnseen);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------------------------------------------- the show ---

  void _start(int index) {
    _clock.stop();
    _progress.value = 0;
    final old = _video;
    _video = null;
    _videoFailed = false;
    unawaited(old?.dispose());
    setState(() => _index = index);

    final moment = _moments[index];
    _see(moment);
    if (moment.isVideo) {
      unawaited(_startVideo(moment));
    } else {
      _clock.duration = photoMomentDuration;
      if (_holds.isEmpty) _clock.forward(from: 0);
    }
  }

  Future<void> _startVideo(Moment moment) async {
    try {
      final url = await ref.read(momentServiceProvider).videoUrl(moment.id);
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted || _current?.id != moment.id) {
        await controller.dispose();
        return;
      }
      controller.addListener(() => _videoTick(controller));
      setState(() => _video = controller);
      if (_holds.isEmpty) await controller.play();
    } catch (_) {
      if (mounted && _current?.id == moment.id) {
        setState(() => _videoFailed = true);
      }
    }
  }

  void _videoTick(VideoPlayerController controller) {
    if (!mounted || !identical(controller, _video)) return;
    final value = controller.value;
    final total = value.duration.inMilliseconds;
    if (total <= 0) return;
    _progress.value = (value.position.inMilliseconds / total).clamp(0.0, 1.0);
    if (value.position >= value.duration && !value.isPlaying) _next();
  }

  void _next() {
    if (!mounted) return;
    if (_index < _moments.length - 1) {
      _start(_index + 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previous() {
    if (_progress.value > 0.15 || _index == 0) {
      _start(_index); // restart this one
    } else {
      _start(_index - 1);
    }
  }

  void _hold(Object reason, bool held) {
    final wasPlaying = _holds.isEmpty;
    held ? _holds.add(reason) : _holds.remove(reason);
    final playing = _holds.isEmpty;
    if (wasPlaying == playing) return;
    final video = _video;
    if (_current?.isVideo ?? false) {
      playing ? video?.play() : video?.pause();
    } else if (playing) {
      _clock.forward();
    } else {
      _clock.stop();
    }
  }

  /// Records that this moment was looked at, and updates the ring when it was
  /// the last unseen one.
  void _see(Moment moment) {
    if (_mine || moment.seen) return;
    // With read receipts off, the owner is not shown that you looked.
    unawaited(
      ref
          .read(momentActionsProvider)
          .markSeen(
            moment,
            private: !ref.read(settingsProvider).sendReadReceipts,
          ),
    );
    final updated = moment.copyWith(seen: true);
    _moments = [for (final m in _moments) m.id == moment.id ? updated : m];
    if (_moments.every((m) => m.seen)) {
      ref.read(momentRingsProvider.notifier).markSeen(widget.userId);
    }
  }

  // --------------------------------------------------------- reacting ---

  Future<void> _toggleLike() async {
    final moment = _current;
    if (moment == null) return;
    HapticFeedback.selectionClick();
    final liked = !moment.liked;
    _replace(
      moment.copyWith(
        liked: liked,
        likeCount: moment.likeCount + (liked ? 1 : -1),
      ),
    );
    try {
      _replace(await ref.read(momentActionsProvider).setLiked(moment, liked));
    } catch (error) {
      _replace(moment);
      _toast(humanError(error, fallback: "Couldn't do that."));
    }
  }

  void _replace(Moment moment) {
    if (!mounted) return;
    setState(() {
      _moments = [for (final m in _moments) m.id == moment.id ? moment : m];
    });
  }

  Future<void> _save() async {
    final moment = _current;
    if (moment == null) return;
    try {
      final where = await ref
          .read(momentActionsProvider)
          .save(moment, ownerLabel: _mine ? 'my-moment' : widget.name);
      _toast(where);
    } catch (error) {
      _toast(humanError(error, fallback: "Couldn't save that."));
    }
  }

  Future<void> _sendReply() async {
    final moment = _current;
    final text = _reply.text.trim();
    final me = ref.read(currentAccountIdProvider);
    if (moment == null || text.isEmpty || me == null || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(chatViewModelProvider.notifier)
          .replyToMoment(
            roomId: ChatViewModel.buildRoomId(me, widget.userId),
            recipientId: widget.userId,
            content: text,
            about: MomentPreview.of(moment),
          );
      if (!mounted) return;
      _reply.clear();
      _replyFocus.unfocus();
      _toast('Reply sent to ${widget.name}.');
    } catch (error) {
      _toast(humanError(error, fallback: "Couldn't send that."));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showViewers() async {
    final moment = _current;
    if (moment == null) return;
    _hold('sheet', true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      isScrollControlled: true,
      builder: (_) => _ViewersSheet(moment: moment),
    );
    _hold('sheet', false);
  }

  Future<void> _delete() async {
    final moment = _current;
    if (moment == null) return;
    _hold('dialog', true);
    final sure =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.paperAlt,
            title: const Text('Delete this moment?'),
            content: const Text('It goes for everyone, now.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              TextButton(
                key: const ValueKey('moment-delete-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    _hold('dialog', false);
    if (!sure || !mounted) return;
    try {
      await ref.read(momentActionsProvider).delete(moment);
    } catch (error) {
      _toast(humanError(error, fallback: "Couldn't delete that."));
      return;
    }
    if (!mounted) return;
    final rest = [
      for (final m in _moments)
        if (m.id != moment.id) m,
    ];
    if (rest.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _moments = rest);
    _start(_index.clamp(0, rest.length - 1));
  }

  // ------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
            ? _error()
            : _show(),
      ),
    );
  }

  Widget _error() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Couldn't load moments.",
          style: AppTextStyles.body.copyWith(color: Colors.white70),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _show() {
    final moment = _current!;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const ValueKey('moment-surface'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) =>
                d.localPosition.dx < box.maxWidth / 3 ? _previous() : _next(),
            onLongPressStart: (_) => _hold('finger', true),
            onLongPressEnd: (_) => _hold('finger', false),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 400) Navigator.of(context).pop();
            },
            child: _content(moment),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _top(moment)),
          Positioned(left: 0, right: 0, bottom: 0, child: _bottom(moment)),
        ],
      ),
    );
  }

  Widget _content(Moment moment) {
    if (moment.isVideo) {
      final video = _video;
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(moment.thumbnail, fit: BoxFit.contain),
          if (video != null && video.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: video.value.aspectRatio,
                child: VideoPlayer(video),
              ),
            ),
          if (_videoFailed)
            Center(
              child: Text(
                "This video can't be played.",
                style: AppTextStyles.body.copyWith(color: Colors.white70),
              ),
            )
          else if (video == null)
            const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    final photo = ref.watch(momentPhotoProvider(moment.id));
    return photo.when(
      data: (bytes) => Image.memory(
        bytes,
        key: ValueKey('moment-photo-${moment.id}'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
      loading: () => Image.memory(
        moment.thumbnail,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
      error: (_, _) => Center(
        child: Text(
          "Couldn't load this photo.",
          style: AppTextStyles.body.copyWith(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _top(Moment moment) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 18),
        child: Column(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, value, _) => Row(
                children: [
                  for (var i = 0; i < _moments.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: MomentProgressBar(
                          key: ValueKey('moment-bar-$i'),
                          value: i < _index ? 1 : (i == _index ? value : 0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                AvatarThumb(size: 34, imageProvider: widget.avatar),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _mine ? 'Your moments' : widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  momentAgo(DateTime.now().difference(moment.createdAt)),
                  style: AppTextStyles.smallDim.copyWith(color: Colors.white70),
                ),
                IconButton(
                  key: const ValueKey('moment-close'),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottom(Moment moment) {
    final caption = moment.caption;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xDD000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (caption != null && caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  caption,
                  key: const ValueKey('moment-caption'),
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.35,
                    shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              ),
            _mine ? _ownerBar(moment) : _replyBar(moment),
          ],
        ),
      ),
    );
  }

  Widget _ownerBar(Moment moment) => Row(
    children: [
      Expanded(
        child: GestureDetector(
          key: const ValueKey('moment-viewers'),
          behavior: HitTestBehavior.opaque,
          onTap: _showViewers,
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                '${moment.viewCount ?? 0}',
                key: const ValueKey('moment-view-count'),
                style: AppTextStyles.body.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.favorite, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                '${moment.likeCount}',
                key: const ValueKey('moment-like-count'),
                style: AppTextStyles.body.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(
                'Who saw it',
                style: AppTextStyles.smallDim.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
      Text(
        'ends in ${momentLeft(moment.timeLeft())}',
        style: AppTextStyles.smallDim.copyWith(color: Colors.white70),
      ),
      IconButton(
        key: const ValueKey('moment-save'),
        icon: const Icon(Icons.download_outlined, color: Colors.white),
        tooltip: 'Save',
        onPressed: _save,
      ),
      IconButton(
        key: const ValueKey('moment-delete'),
        icon: const Icon(Icons.delete_outline, color: Colors.white),
        tooltip: 'Delete',
        onPressed: _delete,
      ),
    ],
  );

  Widget _replyBar(Moment moment) => Row(
    children: [
      Expanded(
        child: TextField(
          key: const ValueKey('moment-reply'),
          controller: _reply,
          focusNode: _replyFocus,
          maxLength: 500,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendReply(),
          style: AppTextStyles.body.copyWith(color: Colors.white),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Reply to ${widget.name}…',
            hintStyle: AppTextStyles.body.copyWith(color: Colors.white54),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: Colors.white54),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: Colors.white),
            ),
          ),
        ),
      ),
      // Hidden when its owner has switched saving off.
      if (moment.allowSave)
        IconButton(
          key: const ValueKey('moment-save'),
          icon: const Icon(Icons.download_outlined, color: Colors.white),
          tooltip: 'Save',
          onPressed: _save,
        ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _reply,
        builder: (_, value, _) => value.text.trim().isEmpty
            ? IconButton(
                key: const ValueKey('moment-like'),
                tooltip: moment.liked ? 'Unlike' : 'Like',
                icon: Icon(
                  moment.liked ? Icons.favorite : Icons.favorite_border,
                  color: moment.liked ? Colors.redAccent : Colors.white,
                ),
                onPressed: _toggleLike,
              )
            : IconButton(
                key: const ValueKey('moment-send-reply'),
                tooltip: 'Send',
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sending ? null : _sendReply,
              ),
      ),
    ],
  );
}

/// Who looked at one of your moments, and who liked it.
class _ViewersSheet extends ConsumerWidget {
  const _ViewersSheet({required this.moment});

  final Moment moment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(momentServiceProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: FutureBuilder<MomentViewers>(
          future: service.viewers(moment.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  humanError(snapshot.error, fallback: "Couldn't load that."),
                  style: AppTextStyles.body,
                ),
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '${data.viewers.length} '
                    '${data.viewers.length == 1 ? 'person' : 'people'} saw this'
                    ' · ${data.likeCount} '
                    '${data.likeCount == 1 ? 'like' : 'likes'}',
                    key: const ValueKey('viewers-title'),
                    style: AppTextStyles.eyebrow,
                  ),
                ),
                if (data.viewers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No one yet.', style: AppTextStyles.smallDim),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final v in data.viewers)
                          ListTile(
                            key: ValueKey('viewer-${v.userId}'),
                            leading: AvatarThumb(
                              size: 38,
                              imageProvider:
                                  v.profilePic == null || v.profilePic!.isEmpty
                                  ? null
                                  : NetworkImage(v.profilePic!),
                            ),
                            title: Text(
                              v.displayName,
                              style: AppTextStyles.body,
                            ),
                            subtitle: Text(
                              '@${v.username} · '
                              '${momentAgo(DateTime.now().difference(v.viewedAt))}',
                              style: AppTextStyles.smallDim,
                            ),
                            trailing: v.liked
                                ? const Icon(
                                    Icons.favorite,
                                    color: Colors.redAccent,
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "just now", "5m", "3h".
String momentAgo(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  return '${d.inHours}h';
}

/// "5 min", "3 h" (what a moment has left).
String momentLeft(Duration d) {
  if (d.inMinutes < 1) return 'moments';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours} h';
}

/// One segment of the strip along the top: a square-cornered bar in the app's
/// own colours, filling as the moment plays.
class MomentProgressBar extends StatelessWidget {
  const MomentProgressBar({super.key, required this.value});

  /// 0 (not played) to 1 (played).
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.55),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: ColoredBox(color: AppColors.primary),
      ),
    );
  }
}
