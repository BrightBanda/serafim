import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/draw_together_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/image_editor/draw_canvas.dart';
import 'package:serafim/src/utils/image_editor/draw_toolbar.dart';
import 'package:serafim/src/utils/image_editor/scribble.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Opens the shared canvas for the session that is waiting or running.
Future<void> openDrawTogether(NavigatorState navigator) => navigator.push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const DrawTogetherPage(),
  ),
);

/// A square sheet two friends draw on at the same time.
class DrawTogetherPage extends ConsumerStatefulWidget {
  const DrawTogetherPage({super.key});

  @override
  ConsumerState<DrawTogetherPage> createState() => _DrawTogetherPageState();
}

class _DrawTogetherPageState extends ConsumerState<DrawTogetherPage> {
  int _color = 1;
  int _width = defaultWidthIndex;
  bool _erasing = false;
  double _side = 1;
  bool _sending = false;

  DrawTogether get _notifier => ref.read(drawTogetherProvider.notifier);

  Offset _norm(Offset p) =>
      Offset((p.dx / _side).clamp(0.0, 1.0), (p.dy / _side).clamp(0.0, 1.0));

  /// Puts the drawing in the chat as a scribble.
  Future<void> _sendToChat(DrawSession session) async {
    final me = ref.read(currentAccountIdProvider);
    if (me == null || _sending || session.strokes.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final png = await renderScribble(
        strokes: [for (final s in session.strokes) s.stroke],
        // The strokes are fractions of the sheet, so "1 wide" scales them.
        displayedWidth: 1,
        paper: scribblePapers[session.paper % scribblePapers.length],
      );
      await ref
          .read(chatViewModelProvider.notifier)
          .sendMessage(
            roomId: ChatViewModel.buildRoomId(me, session.peerId),
            recipientId: session.peerId,
            imageBytes: png,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Sent to the chat.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _leave(DrawSession? session) async {
    if (session == null || session.status == DrawStatus.ended) {
      _notifier.close();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (session.status == DrawStatus.live && session.strokes.isNotEmpty) {
      final stop = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.paperAlt,
          title: const Text('Stop drawing together?'),
          content: const Text(
            'The drawing is not saved unless you send it to the chat first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep drawing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop'),
            ),
          ],
        ),
      );
      if (stop != true) return;
    }
    _notifier.leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(drawTogetherProvider);
    // Nothing to show once the session is gone (declined, timed out, closed).
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(backgroundColor: Colors.black);
    }
    final peer = ref.watch(knownPersonProvider(session.peerId));
    final name = peer?.displayName ?? 'your friend';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(session);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            session.status == DrawStatus.live
                ? 'Drawing with $name'
                : 'Draw together',
          ),
          leading: IconButton(
            key: const ValueKey('draw-leave'),
            icon: const Icon(Icons.close),
            onPressed: () => _leave(session),
          ),
          actions: [
            if (session.strokes.isNotEmpty &&
                session.status != DrawStatus.invited)
              TextButton(
                key: const ValueKey('draw-send-to-chat'),
                onPressed: _sending ? null : () => _sendToChat(session),
                child: const Text(
                  'SEND TO CHAT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (session.status) {
            DrawStatus.invited => _Invitation(
              name: name,
              onJoin: _notifier.join,
              onDecline: () {
                _notifier.decline();
                if (mounted) Navigator.of(context).pop();
              },
            ),
            DrawStatus.waiting => _Notice(
              busy: true,
              text: 'Waiting for $name to join…',
              actionLabel: 'Cancel',
              onAction: () => _leave(session),
            ),
            _ => _canvas(session, name),
          },
        ),
      ),
    );
  }

  Widget _canvas(DrawSession session, String name) {
    final ended = session.status == DrawStatus.ended;
    final paper = scribblePapers[session.paper % scribblePapers.length];
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final side =
                  (box.maxWidth < box.maxHeight
                      ? box.maxWidth
                      : box.maxHeight) -
                  32;
              _side = side;
              return Center(
                child: Stack(
                  children: [
                    Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        color: paper,
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      child: GestureDetector(
                        key: const ValueKey('together-pad'),
                        onPanStart: ended
                            ? null
                            : (d) => _notifier.beginStroke(
                                color: drawColors[_color],
                                widthIndex: _width,
                                erase: _erasing,
                                point: _norm(d.localPosition),
                              ),
                        onPanUpdate: ended
                            ? null
                            : (d) => _notifier.extendStroke(
                                _norm(d.localPosition),
                              ),
                        onPanEnd: ended ? null : (_) => _notifier.endStroke(),
                        onPanCancel: ended ? null : _notifier.endStroke,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: StrokePainter(
                              strokes: [
                                for (final s in session.strokes) s.stroke,
                              ],
                              scale: side,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                    if (ended)
                      Positioned.fill(
                        child: Container(
                          width: side,
                          height: side,
                          color: Colors.black54,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            session.endedBecause ?? 'It ended.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.displayHeading.copyWith(
                              fontSize: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (!ended)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: DrawToolbar(
              color: _color,
              width: _width,
              onColor: (i) => setState(() {
                _color = i;
                _erasing = false;
              }),
              onWidth: (i) => setState(() => _width = i),
              erasing: _erasing,
              onEraser: () => setState(() => _erasing = !_erasing),
              hasStrokes: session.strokes.any((s) => s.mine),
              onUndo: _notifier.undo,
              onClear: _notifier.clear,
              extra: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < scribblePapers.length; i++)
                    GestureDetector(
                      key: ValueKey('together-paper-$i'),
                      onTap: () => _notifier.setPaper(i),
                      child: Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: scribblePapers[i],
                          border: Border.all(
                            color: i == session.paper
                                ? Colors.white
                                : Colors.white24,
                            width: i == session.paper ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: () => _leave(session),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

class _Invitation extends StatelessWidget {
  const _Invitation({
    required this.name,
    required this.onJoin,
    required this.onDecline,
  });

  final String name;
  final VoidCallback onJoin;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.draw_outlined, size: 44, color: Colors.white),
            const SizedBox(height: 14),
            Text(
              '$name wants to draw together',
              textAlign: TextAlign.center,
              style: AppTextStyles.displayHeading.copyWith(
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('together-join'),
              onPressed: onJoin,
              child: const Text('JOIN'),
            ),
            TextButton(
              key: const ValueKey('together-decline'),
              onPressed: onDecline,
              child: const Text(
                'Not now',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
  });

  final String text;
  final bool busy;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(text, style: const TextStyle(color: Colors.white)),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
