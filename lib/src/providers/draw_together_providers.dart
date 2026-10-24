import 'dart:async';

import 'package:serafim/src/core/debug_log.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

/// Draw Together: two friends draw on one canvas, live.
///
/// Everything here is live-only. The server relays the frames and keeps
/// nothing; the drawing exists on the two phones until someone sends it to the
/// chat as a scribble. Coordinates travel as fractions of the square (0..1) and
/// pen widths as a fraction of its width, so different screens agree.

/// How thick pens are on the shared sheet, per [drawWidths] unit: a pen of
/// size 8 is `8 / referencePadWidth` of the sheet, whatever the screen.
const double referencePadWidth = 360;

enum DrawStatus {
  /// We asked; waiting for them to join.
  waiting,

  /// They asked; waiting for us to join.
  invited,

  /// Both here, drawing.
  live,

  /// Over (see [DrawSession.endedBecause]).
  ended,
}

/// One line on the shared sheet and who drew it.
class SharedStroke {
  SharedStroke({required this.key, required this.mine, required this.stroke});

  /// Unique on this sheet: `<owner>:<id>`.
  final String key;
  final bool mine;
  final Stroke stroke;
  bool done = false;
}

class DrawSession {
  DrawSession({
    required this.id,
    required this.peerId,
    required this.status,
    this.paper = 0,
    this.endedBecause,
    List<SharedStroke>? strokes,
    this.version = 0,
  }) : strokes = strokes ?? [];

  final String id;
  final String peerId;
  final DrawStatus status;
  final int paper;

  /// Why it ended, in words for the screen.
  final String? endedBecause;
  final List<SharedStroke> strokes;

  /// Bumped on every change, so painters know to redraw.
  final int version;

  DrawSession copyWith({
    DrawStatus? status,
    int? paper,
    String? endedBecause,
  }) => DrawSession(
    id: id,
    peerId: peerId,
    status: status ?? this.status,
    paper: paper ?? this.paper,
    endedBecause: endedBecause ?? this.endedBecause,
    strokes: strokes,
    version: version + 1,
  );

  DrawSession touched() => copyWith();
}

class DrawTogether extends Notifier<DrawSession?> {
  static const inviteWaits = Duration(seconds: 45);
  static const inviteRepeatEvery = Duration(seconds: 4);
  static const maxInviteSends = 8;
  static const joinRepeatEvery = Duration(milliseconds: 1500);
  static const maxJoinSends = 5;
  static const flushEvery = Duration(milliseconds: 60);

  Timer? _inviteTimer;
  Timer? _inviteResend;
  Timer? _joinRetry;
  Timer? _flush;
  int _inviteSent = 0;
  int _joinSent = 0;

  /// Whether the other side has said anything in this session yet. Control
  /// messages (invite, join, decline) are sent only once by the connection, and
  /// mobile networks drop messages, so they are repeated until this is true.
  bool _heardPeer = false;
  int _nextStroke = 0;
  SharedStroke? _drawing;
  final List<double> _unsent = [];

  @override
  DrawSession? build() {
    ref.onDispose(() {
      _inviteTimer?.cancel();
      _inviteResend?.cancel();
      _joinRetry?.cancel();
      _flush?.cancel();
    });
    return null;
  }

  String? get _me => ref.read(currentAccountIdProvider);

  bool get busy => state != null && state!.status != DrawStatus.ended;

  bool _send(Map<String, dynamic> frame) {
    final session = state;
    if (session == null) return false;
    return _sendTo(session.id, session.peerId, frame);
  }

  bool _sendTo(String session, String peer, Map<String, dynamic> frame) {
    final sent = ref.read(webSocketServiceProvider).sendMessage({
      'type': 'draw',
      'session': session,
      'recipient_id': peer,
      ...frame,
    });
    if (frame['op'] != 'stroke') {
      trace('draw', 'send ${frame['op']} session=$session to=$peer ok=$sent');
    }
    return sent;
  }

  // ----------------------------------------------------------- starting ---

  /// Asks [peerId] to draw together. False if already in a session or the
  /// connection is down.
  bool invite(String peerId) {
    if (busy || _me == null) return false;
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    _resetHandshake();
    state = DrawSession(id: id, peerId: peerId, status: DrawStatus.waiting);
    if (!_send({'op': 'invite'})) {
      _end('Could not reach them. Check your connection.');
      return false;
    }
    _inviteSent = 1;
    // Ask again every few seconds until they answer: one invitation can be
    // lost on the way, and they ignore the repeats.
    _inviteResend = Timer.periodic(inviteRepeatEvery, (timer) {
      if (state?.status != DrawStatus.waiting ||
          _heardPeer ||
          ++_inviteSent > maxInviteSends) {
        timer.cancel();
        return;
      }
      _send({'op': 'invite'});
    });
    _inviteTimer?.cancel();
    _inviteTimer = Timer(inviteWaits, () {
      if (state?.status == DrawStatus.waiting) _end('No answer.');
    });
    return true;
  }

  /// Accepts the invitation that is waiting.
  void join() {
    final s = state;
    if (s == null || s.status != DrawStatus.invited) return;
    _inviteTimer?.cancel();
    state = s.copyWith(status: DrawStatus.live);
    _send({'op': 'join'});
    // Say it again until they answer (a "ready", or any stroke): if the first
    // one is lost, they would wait for ever.
    _joinSent = 1;
    _joinRetry?.cancel();
    _joinRetry = Timer.periodic(joinRepeatEvery, (timer) {
      if (state?.id != s.id || _heardPeer || ++_joinSent > maxJoinSends) {
        timer.cancel();
        return;
      }
      _send({'op': 'join'});
    });
  }

  /// Turns the invitation down.
  void decline() {
    final s = state;
    if (s == null || s.status != DrawStatus.invited) return;
    // The answer matters, and it is the last thing sent, so it goes three
    // times, a second apart. They ignore any after the first.
    _sendTo(s.id, s.peerId, {'op': 'decline'});
    for (final seconds in const [1, 2]) {
      Future<void>.delayed(Duration(seconds: seconds), () {
        if (ref.mounted) _sendTo(s.id, s.peerId, {'op': 'decline'});
      });
    }
    close();
  }

  // ---------------------------------------------------------- incoming ---

  /// A `draw` frame from the server. Returns true when it is a *new*
  /// invitation, so the caller can alert the person.
  bool heard(Map<String, dynamic> frame) {
    if (frame['op'] != 'stroke') {
      final s = state;
      trace(
        'draw',
        'heard ${frame['op']} from=${frame['sender_id']} '
            'session=${frame['session']} | mine: '
            '${s == null ? 'none' : '${s.status.name} id=${s.id} peer=${s.peerId}'}',
      );
    }
    final from = frame['sender_id'] as String?;
    final session = frame['session'] as String?;
    final op = frame['op'] as String?;
    if (from == null || session == null || op == null) return false;

    if (op == 'invite') {
      // The same invitation again (they repeat it): nothing new.
      if (state?.id == session && state?.peerId == from) return false;
      if (busy) {
        // Already drawing with someone: tell them, don't change anything.
        ref.read(webSocketServiceProvider).sendMessage({
          'type': 'draw',
          'op': 'busy',
          'session': session,
          'recipient_id': from,
        });
        return false;
      }
      state = DrawSession(
        id: session,
        peerId: from,
        status: DrawStatus.invited,
      );
      _inviteTimer?.cancel();
      _inviteTimer = Timer(const Duration(seconds: 60), () {
        if (state?.status == DrawStatus.invited) close();
      });
      return true;
    }

    final s = state;
    if (s == null || s.id != session || s.peerId != from) return false;

    // Anything from them means they are there and heard us.
    _heardPeer = true;
    _inviteResend?.cancel();
    _joinRetry?.cancel();

    // They are drawing, so they have joined — even if their "join" got lost.
    const joinedOps = {'join', 'ready', 'stroke', 'undo', 'clear', 'paper'};
    var current = s;
    if (s.status == DrawStatus.waiting && joinedOps.contains(op)) {
      _inviteTimer?.cancel();
      current = s.copyWith(status: DrawStatus.live);
      state = current;
    }

    switch (op) {
      case 'join':
        // Tell them we saw it (also when it is a repeat of one we saw).
        _send({'op': 'ready'});
      case 'ready':
        break;
      case 'stroke':
        if (current.status == DrawStatus.live) _remoteStroke(current, frame);
      case 'undo':
        final key = '$from:${frame['id']}';
        current.strokes.removeWhere((x) => x.key == key);
        state = current.touched();
      case 'clear':
        current.strokes.clear();
        state = current.touched();
      case 'paper':
        final i = frame['i'];
        if (i is int) state = current.copyWith(paper: i);
      case 'leave':
        _end('They left.');
      case 'decline':
        _end('They declined.');
      case 'busy':
        _end('They are already drawing with someone.');
      case 'unavailable':
        _end('They are not available right now.');
    }
    return false;
  }

  void _remoteStroke(DrawSession s, Map<String, dynamic> frame) {
    final key = '${s.peerId}:${frame['id']}';
    var shared = s.strokes.where((x) => x.key == key).firstOrNull;
    if (shared == null) {
      final colour = frame['c'];
      final width = frame['w'];
      shared = SharedStroke(
        key: key,
        mine: false,
        stroke: Stroke(
          color: Color(colour is int ? colour : 0xFF000000),
          width: width is num ? width.toDouble() : 0.02,
          erase: frame['e'] == true,
        ),
      );
      s.strokes.add(shared);
    }
    final p = frame['p'];
    if (p is List) {
      for (var i = 0; i + 1 < p.length; i += 2) {
        final x = p[i], y = p[i + 1];
        if (x is num && y is num) {
          shared.stroke.points.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    if (frame['done'] == true) shared.done = true;
    state = s.touched();
  }

  // --------------------------------------------------- drawing locally ---

  /// Starts a line at [point] (0..1 on the sheet).
  void beginStroke({
    required Color color,
    required int widthIndex,
    required bool erase,
    required Offset point,
  }) {
    final s = state;
    if (s == null || s.status != DrawStatus.live) return;
    final id = '${_nextStroke++}';
    final width =
        drawWidths[widthIndex] *
        (erase ? eraserWidthFactor : 1) /
        referencePadWidth;
    final shared = SharedStroke(
      key: '${_me ?? 'me'}:$id',
      mine: true,
      stroke: Stroke(color: color, width: width, erase: erase, points: [point]),
    );
    _drawing = shared;
    _unsent
      ..clear()
      ..addAll([point.dx, point.dy]);
    s.strokes.add(shared);
    state = s.touched();
    _flush ??= Timer.periodic(flushEvery, (_) => _flushNow());
  }

  void extendStroke(Offset point) {
    final s = state;
    final drawing = _drawing;
    if (s == null || drawing == null) return;
    drawing.stroke.points.add(point);
    _unsent.addAll([point.dx, point.dy]);
    state = s.touched();
  }

  void endStroke() {
    final drawing = _drawing;
    if (drawing == null) return;
    drawing.done = true;
    _flushNow(done: true);
    _drawing = null;
    _flush?.cancel();
    _flush = null;
  }

  /// Sends what has been drawn since the last time, in one small frame.
  void _flushNow({bool done = false}) {
    final drawing = _drawing;
    if (drawing == null || (_unsent.isEmpty && !done)) return;
    final id = drawing.key.split(':').last;
    final points = List<double>.of(_unsent);
    _unsent.clear();
    _sendFrame(drawing.stroke, id, points, done);
  }

  void _sendFrame(Stroke stroke, String id, List<double> points, bool done) {
    _send({
      'op': 'stroke',
      'id': id,
      'c': stroke.color.toARGB32(),
      'w': stroke.width,
      'e': stroke.erase,
      'p': points,
      'done': done,
    });
  }

  /// Takes back my last line.
  void undo() {
    final s = state;
    if (s == null || s.status != DrawStatus.live) return;
    final index = s.strokes.lastIndexWhere((x) => x.mine);
    if (index < 0) return;
    final removed = s.strokes.removeAt(index);
    _send({'op': 'undo', 'id': removed.key.split(':').last});
    state = s.touched();
  }

  /// Wipes the sheet for both of us.
  void clear() {
    final s = state;
    if (s == null || s.status != DrawStatus.live) return;
    s.strokes.clear();
    _send({'op': 'clear'});
    state = s.touched();
  }

  void setPaper(int index) {
    final s = state;
    if (s == null || s.status != DrawStatus.live) return;
    state = s.copyWith(paper: index);
    _send({'op': 'paper', 'i': index});
  }

  // ------------------------------------------------------------- ending ---

  /// I am leaving.
  void leave() {
    if (state == null) return;
    if (state!.status != DrawStatus.ended) _send({'op': 'leave'});
    close();
  }

  void _resetHandshake() {
    _inviteResend?.cancel();
    _joinRetry?.cancel();
    _heardPeer = false;
    _inviteSent = 0;
    _joinSent = 0;
  }

  void _end(String reason) {
    trace('draw', 'ended: $reason');
    _resetHandshake();
    _inviteTimer?.cancel();
    _flush?.cancel();
    _flush = null;
    _drawing = null;
    final s = state;
    if (s == null) return;
    state = s.copyWith(status: DrawStatus.ended, endedBecause: reason);
  }

  /// Forget the session (after it has ended, or I left).
  void close() {
    _resetHandshake();
    _inviteTimer?.cancel();
    _flush?.cancel();
    _flush = null;
    _drawing = null;
    state = null;
  }
}

final drawTogetherProvider = NotifierProvider<DrawTogether, DrawSession?>(
  DrawTogether.new,
);
