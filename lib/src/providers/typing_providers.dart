import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';

/// Who is typing, per conversation: room id → ids of the people typing in it.
///
/// Fed by the socket's `typing` events. Nothing is stored. A person counts as
/// typing for [typingExpiry] after their last event, so a lost "stopped"
/// (they closed the app, the connection dropped) cannot leave "typing…" up
/// forever.
class TypingNotifier extends Notifier<Map<String, Set<String>>> {
  /// Longer than how often a phone repeats "still typing" (see
  /// `TypingBroadcaster`), so a steady typist never flickers.
  static const typingExpiry = Duration(seconds: 6);

  final Map<(String, String), Timer> _timers = {};

  @override
  Map<String, Set<String>> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  /// A `typing` event from the server.
  void heard(Map<String, dynamic> event) {
    final me = ref.read(currentAccountIdProvider);
    final sender = event['sender_id'] as String?;
    if (me == null || sender == null || sender == me) return;
    final group = event['group_id'] as String?;
    final room = group != null
        ? groupRoomId(group)
        : ChatViewModel.buildRoomId(me, sender);
    if (event['state'] == false) {
      stopped(room, sender);
    } else {
      _start(room, sender);
    }
  }

  /// [sender] is no longer typing in [room] — they stopped, or just sent
  /// their message.
  void stopped(String room, String sender) {
    _timers.remove((room, sender))?.cancel();
    final here = state[room];
    if (here == null || !here.contains(sender)) return;
    final left = {...here}..remove(sender);
    state = {...state, room: left}..removeWhere((_, v) => v.isEmpty);
  }

  void _start(String room, String sender) {
    _timers[(room, sender)]?.cancel();
    _timers[(room, sender)] = Timer(typingExpiry, () => stopped(room, sender));
    final here = state[room] ?? const <String>{};
    if (here.contains(sender)) return;
    state = {
      ...state,
      room: {...here, sender},
    };
  }
}

final typingProvider =
    NotifierProvider<TypingNotifier, Map<String, Set<String>>>(
      TypingNotifier.new,
    );

/// The people typing in one conversation. Only rebuilds listeners of *that*
/// conversation, so a chat list row is untouched by typing elsewhere.
final typingInRoomProvider = Provider.family<Set<String>, String>(
  (ref, room) =>
      ref.watch(typingProvider.select((m) => m[room] ?? const <String>{})),
);
