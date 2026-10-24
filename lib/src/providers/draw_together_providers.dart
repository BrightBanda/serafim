import 'dart:async';

import 'package:serafim/src/core/debug_log.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';

/// Draw Together: two friends draw on one canvas, live.
///
/// The server owns each session — who invited whom, whether it was answered,
/// and what is on the canvas — and tells both phones (see the protocol at the
/// top of the server's draw section in `app/api/ws.py`). This side follows
/// what it says, so the two phones never have to guess each other's state,
/// and a phone that reconnects is handed the whole drawing again.
///
/// Coordinates travel as fractions of the square (0..1) and pen widths as a
/// fraction of its width, so different screens agree.

/// How thick pens are on the shared sheet, per [drawWidths] unit: a pen of
/// size 8 is `8 / referencePadWidth` of the sheet, whatever the screen.
const double referencePadWidth = 360;

enum DrawStatus {
  /// We asked; waiting for them to join.
  waiting,

  /// They asked; waiting for us to answer.
  invited,

  /// We said yes; waiting for the server to start it.
  joining,

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
    this.peerAway = false,
    List<SharedStroke>? strokes,
    this.version = 0,
  }) : strokes = strokes ?? [];

  /// The server's id for it. Null only while our invitation is on its way.
  final String? id;
  final String peerId;
  final DrawStatus status;
  final int paper;

  /// Why it ended, in words for the screen.
  final String? endedBecause;

  /// The other person's connection dropped; the server waits a little for
  /// them before ending it.
  final bool peerAway;
  final List<SharedStroke> strokes;

  /// Bumped on every change, so painters know to redraw.
  final int version;

  DrawSession copyWith({
    String? id,
    DrawStatus? status,
    int? paper,
    String? endedBecause,
    bool? peerAway,
    List<SharedStroke>? strokes,
  }) => DrawSession(
    id: id ?? this.id,
    peerId: peerId,
    status: status ?? this.status,
    paper: paper ?? this.paper,
    endedBecause: endedBecause ?? this.endedBecause,
    peerAway: peerAway ?? this.peerAway,
    strokes: strokes ?? this.strokes,
    version: version + 1,
  );

  DrawSession touched() => copyWith();
}

/// Words for why a session ended (or never started), from the server's
/// reason.
String drawEndedText(String? reason) => switch (reason) {
  'declined' => 'They said not now.',
  'cancelled' => 'They cancelled the invitation.',
  'left' => 'They left.',
  'expired' => 'The invitation expired.',
  'lost' => 'They lost their connection.',
  'gone' => 'This drawing has already ended.',
  'not_friends' => 'You can only draw with friends.',
  'busy' => 'They are already drawing with someone.',
  'you_are_busy' => 'You are already drawing with someone.',
  'no_connection' => 'Could not reach them. Check your connection.',
  'no_answer' => 'No answer.',
  _ => 'It ended.',
};

class DrawTogether extends Notifier<DrawSession?> {
  /// How long to wait for the server before giving up on our own: it ends
  /// invitations after 60 seconds and always says so, unless the link died.
  static const inviteWaits = Duration(seconds: 70);
  static const joinWaits = Duration(seconds: 15);
  static const flushEvery = Duration(milliseconds: 60);

  Timer? _giveUp;
  Timer? _flush;
  int _nextStroke = 0;
  SharedStroke? _drawing;
  final List<double> _unsent = [];

  /// Whom we invited and then cancelled before the server had named the
  /// session: it is left as soon as it is named.
  String? _cancelledInviteTo;

  @override
  DrawSession? build() {
    ref.onDispose(() {
      _giveUp?.cancel();
      _flush?.cancel();
    });
    return null;
  }

  String? get _me => ref.read(currentAccountIdProvider);

  /// In a session that has not ended.
  bool get busy => state != null && state!.status != DrawStatus.ended;

  bool _send(Map<String, dynamic> frame) {
    final sent = ref.read(webSocketServiceProvider).sendMessage({
      'type': 'draw',
      ...frame,
    });
    if (frame['op'] != 'stroke') trace('draw', 'send ${frame['op']} ok=$sent');
    return sent;
  }

  bool _sendInSession(Map<String, dynamic> frame) {
    final id = state?.id;
    if (id == null) return false;
    return _send({'session': id, ...frame});
  }

  void _waitAtMost(Duration wait, DrawStatus status, String reason) {
    _giveUp?.cancel();
    _giveUp = Timer(wait, () {
      if (state?.status == status) _end(reason);
    });
  }

  // ----------------------------------------------------------- starting ---

  /// Asks [peerId] to draw together. False if already in a session or the
  /// connection is down.
  bool invite(String peerId) {
    if (busy || _me == null) return false;
    _cancelledInviteTo = null;
    state = DrawSession(id: null, peerId: peerId, status: DrawStatus.waiting);
    if (!_send({'op': 'invite', 'recipient_id': peerId})) {
      _end(drawEndedText('no_connection'));
      return false;
    }
    _waitAtMost(inviteWaits, DrawStatus.waiting, drawEndedText('no_answer'));
    return true;
  }

  /// An invitation known from a tapped push before the app's connection has
  /// delivered it. The server hands it over on connect (or says it is gone).
  void expectInvite({required String session, required String peerId}) {
    if (busy) return;
    state = DrawSession(
      id: session,
      peerId: peerId,
      status: DrawStatus.invited,
    );
    _expireInvitation(null);
  }

  /// An invitation nobody answers goes away when the server's does (it says
  /// so, but not if the link is down), with a little slack.
  void _expireInvitation(Object? seconds) {
    final wait = Duration(seconds: (seconds is int ? seconds : 60) + 5);
    _waitAtMost(wait, DrawStatus.invited, drawEndedText('expired'));
  }

  /// Accepts the invitation that is waiting.
  void join() {
    final s = state;
    if (s == null || s.status != DrawStatus.invited) return;
    state = s.copyWith(status: DrawStatus.joining);
    if (!_sendInSession({'op': 'join'})) {
      _end(drawEndedText('no_connection'));
      return;
    }
    _waitAtMost(joinWaits, DrawStatus.joining, drawEndedText('no_connection'));
  }

  /// Turns the invitation down.
  void decline() {
    final s = state;
    if (s == null || s.status != DrawStatus.invited) return;
    _sendInSession({'op': 'decline'});
    close();
  }

  // ---------------------------------------------------------- incoming ---

  /// A `draw` frame from the server. Returns true when it is a *new*
  /// invitation, so the caller can alert the person.
  bool heard(Map<String, dynamic> frame) {
    final op = frame['op'] as String?;
    final session = frame['session'] as String?;
    if (op != 'stroke') {
      final s = state;
      trace(
        'draw',
        'heard $op session=$session | mine: '
            '${s == null ? 'none' : '${s.status.name} id=${s.id}'}',
      );
    }
    switch (op) {
      case 'invite':
        final from = frame['peer_id'] as String?;
        if (session == null || from == null) return false;
        // The same one again (it can arrive live and again on connect).
        if (state?.id == session) return false;
        if (busy) return false; // the server does not let this happen
        state = DrawSession(
          id: session,
          peerId: from,
          status: DrawStatus.invited,
        );
        _expireInvitation(frame['expires_in']);
        return true;

      case 'invited':
        final peer = frame['peer_id'] as String?;
        if (session != null && peer != null && _cancelledInviteTo == peer) {
          // Cancelled while it was on its way: withdraw it now.
          _cancelledInviteTo = null;
          _send({'op': 'leave', 'session': session});
          return false;
        }
        final s = state;
        if (s == null || s.status != DrawStatus.waiting || s.peerId != peer) {
          return false;
        }
        state = s.copyWith(id: session);
        return false;

      case 'refused':
        final s = state;
        if (s != null &&
            s.status == DrawStatus.waiting &&
            s.peerId == frame['peer_id']) {
          _end(drawEndedText(frame['reason'] as String?));
        }
        return false;
    }

    // Everything else is about a named session we are in.
    final s = state;
    if (s == null || session == null || s.id != session) return false;

    switch (op) {
      case 'started':
      case 'state':
        _giveUp?.cancel();
        state = s.copyWith(
          status: DrawStatus.live,
          paper: frame['paper'] is int ? frame['paper'] as int : 0,
          peerAway: false,
          strokes: _strokesFrom(frame['strokes']),
        );
      case 'stroke':
        if (s.status == DrawStatus.live) _remoteStroke(s, frame);
      case 'undo':
        final key = '${s.peerId}:${frame['id']}';
        s.strokes.removeWhere((x) => x.key == key);
        state = s.touched();
      case 'clear':
        s.strokes.clear();
        state = s.touched();
      case 'paper':
        final i = frame['i'];
        if (i is int) state = s.copyWith(paper: i);
      case 'away':
        state = s.copyWith(peerAway: true);
      case 'back':
        state = s.copyWith(peerAway: false);
      case 'ended':
        _end(drawEndedText(frame['reason'] as String?));
    }
    return false;
  }

  /// The canvas as the server keeps it (on start, or after reconnecting).
  List<SharedStroke> _strokesFrom(Object? raw) {
    final me = _me;
    final strokes = <SharedStroke>[];
    if (raw is! List) return strokes;
    for (final item in raw) {
      if (item is! Map) continue;
      final owner = item['owner'] as String? ?? '';
      final shared = _strokeFrom(
        key: '$owner:${item['id']}',
        mine: owner == me,
        frame: item,
      );
      strokes.add(shared);
      // Our own numbering continues past anything already on the sheet.
      final n = int.tryParse('${item['id']}');
      if (owner == me && n != null && n >= _nextStroke) _nextStroke = n + 1;
    }
    return strokes;
  }

  SharedStroke _strokeFrom({
    required String key,
    required bool mine,
    required Map<dynamic, dynamic> frame,
  }) {
    final colour = frame['c'];
    final width = frame['w'];
    final shared = SharedStroke(
      key: key,
      mine: mine,
      stroke: Stroke(
        color: Color(colour is int ? colour : 0xFF000000),
        width: width is num ? width.toDouble() : 0.02,
        erase: frame['e'] == true,
      ),
    );
    _addPoints(shared, frame);
    return shared;
  }

  void _addPoints(SharedStroke shared, Map<dynamic, dynamic> frame) {
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
  }

  void _remoteStroke(DrawSession s, Map<String, dynamic> frame) {
    final key = '${s.peerId}:${frame['id']}';
    final existing = s.strokes.where((x) => x.key == key).firstOrNull;
    if (existing == null) {
      s.strokes.add(_strokeFrom(key: key, mine: false, frame: frame));
    } else {
      _addPoints(existing, frame);
    }
    state = s.touched();
  }

  // --------------------------------------------------- drawing locally ---

  /// Starts a line at [point] (0..1 on the sheet). [widthIndex] is a pen
  /// size, or an eraser size when [erase] is set.
  void beginStroke({
    required Color color,
    required int widthIndex,
    required bool erase,
    required Offset point,
  }) {
    final s = state;
    if (s == null || s.status != DrawStatus.live) return;
    final id = '${_nextStroke++}';
    final width = strokeWidthFor(widthIndex, erase: erase) / referencePadWidth;
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
    final points = List<double>.of(_unsent);
    _unsent.clear();
    _sendInSession({
      'op': 'stroke',
      'id': drawing.key.split(':').last,
      'c': drawing.stroke.color.toARGB32(),
      'w': drawing.stroke.width,
      'e': drawing.stroke.erase,
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
    _sendInSession({'op': 'undo', 'id': removed.key.split(':').last});
    state = s.touched();
  }

  /// Wipes the sheet for both of us.
  void clear() {
    final s = state;
    if (s == null || s.status != DrawStatus.live) return;
    s.strokes.clear();
    _sendInSession({'op': 'clear'});
    state = s.touched();
  }

  void setPaper(int index) {
    final s = state;
    if (s == null || s.status != DrawStatus.live) return;
    state = s.copyWith(paper: index);
    _sendInSession({'op': 'paper', 'i': index});
  }

  // ------------------------------------------------------------- ending ---

  /// I am leaving (or cancelling my invitation). The other person is told.
  void leave() {
    final s = state;
    if (s == null) return;
    if (s.status != DrawStatus.ended) {
      if (s.id == null) {
        // Not named yet: withdraw it the moment the server names it.
        _cancelledInviteTo = s.peerId;
        close();
        return;
      }
      _sendInSession({'op': 'leave'});
    }
    close();
  }

  void _end(String reason) {
    trace('draw', 'ended: $reason');
    _giveUp?.cancel();
    _flush?.cancel();
    _flush = null;
    _drawing = null;
    final s = state;
    if (s == null) return;
    state = s.copyWith(status: DrawStatus.ended, endedBecause: reason);
  }

  /// Forget the session (after it has ended, or I left).
  void close() {
    _giveUp?.cancel();
    _flush?.cancel();
    _flush = null;
    _drawing = null;
    _nextStroke = 0;
    state = null;
  }
}

final drawTogetherProvider = NotifierProvider<DrawTogether, DrawSession?>(
  DrawTogether.new,
);
