import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/group.dart' show groupRoomId;
import 'package:serafim/src/data/services/chat_features_service.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

final chatFeaturesServiceProvider = Provider<ChatFeaturesService>(
  (ref) => ChatFeaturesService(ref.watch(apiDioProvider)),
);

/// The local room id for [chat], as seen by [me].
String roomIdOfChat(String me, ChatRef chat) => chat.isGroup
    ? groupRoomId(chat.id)
    : ChatViewModel.buildRoomId(me, chat.id);

/// Per-chat features by room id, for every chat whose features were
/// changed (the rest are at [ChatFeatures.defaults]).
///
/// Local-first: kept in preferences so they apply before the network
/// answers; refreshed from the server at start and on reconnect, and
/// updated live by `chat_settings` frames.
class ChatFeaturesController extends Notifier<Map<String, ChatFeatures>> {
  static String _key(String me) => 'chat_features.v1.$me';

  /// Rooms changed (heard, loaded or set) while a refresh was in flight:
  /// newer than the list it brings back, so they are kept.
  final _touched = <String>{};

  @override
  Map<String, ChatFeatures> build() {
    final me = ref.watch(currentAccountIdProvider);
    if (me == null) return const {};
    final raw = ref.read(sharedPreferencesProvider).getString(_key(me));
    var saved = const <String, ChatFeatures>{};
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        saved = {
          for (final e in map.entries)
            e.key: ChatFeatures.fromJson(e.value as Map<String, dynamic>),
        };
      } catch (_) {}
    }
    Future.microtask(refresh);
    return saved;
  }

  /// Takes the server's list as the truth.
  Future<void> refresh() async {
    final me = ref.read(currentAccountIdProvider);
    if (me == null) return;
    _touched.clear();
    try {
      final list = await ref.read(chatFeaturesServiceProvider).all();
      if (!ref.mounted || ref.read(currentAccountIdProvider) != me) return;
      _save({
        for (final e in list) roomIdOfChat(me, e.chat): e.features,
        for (final room in _touched)
          if (state[room] case final f?) room: f,
      });
    } catch (_) {
      // Offline: what was saved stays.
    }
  }

  /// A `chat_settings` frame: someone in the chat changed it.
  void heard(Map<String, dynamic> data) {
    final me = ref.read(currentAccountIdProvider);
    if (me == null || data['id'] == null) return;
    final e = ChatFeaturesService.entryOf(data);
    _put(roomIdOfChat(me, e.chat), e.features);
  }

  /// Asks the server for one chat (opening its features page).
  Future<void> load(ChatRef chat) async {
    final me = ref.read(currentAccountIdProvider);
    if (me == null) return;
    final got = await ref.read(chatFeaturesServiceProvider).get(chat);
    if (!ref.mounted) return;
    _put(roomIdOfChat(me, chat), got);
  }

  /// Changes [chat] for everyone in it. Shows at once; undone if the server
  /// refuses.
  Future<void> setHideDeleted(ChatRef chat, bool hide) async {
    final me = ref.read(currentAccountIdProvider);
    if (me == null) return;
    final room = roomIdOfChat(me, chat);
    final before = state[room] ?? ChatFeatures.defaults;
    _put(room, before.copyWith(hideDeleted: hide));
    try {
      final got = await ref
          .read(chatFeaturesServiceProvider)
          .set(chat, hideDeleted: hide);
      if (ref.mounted) _put(room, got);
    } catch (_) {
      if (ref.mounted) _put(room, before);
      rethrow;
    }
  }

  void _put(String room, ChatFeatures features) {
    _touched.add(room);
    _save({...state, room: features});
  }

  void _save(Map<String, ChatFeatures> next) {
    state = next;
    final me = ref.read(currentAccountIdProvider);
    if (me == null) return;
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(
            _key(me),
            jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}),
          ),
    );
  }
}

final chatFeaturesControllerProvider =
    NotifierProvider<ChatFeaturesController, Map<String, ChatFeatures>>(
      ChatFeaturesController.new,
    );

/// One chat's features (by room id).
final chatFeaturesProvider = Provider.family<ChatFeatures, String>(
  (ref, roomId) => ref.watch(
    chatFeaturesControllerProvider.select(
      (m) => m[roomId] ?? ChatFeatures.defaults,
    ),
  ),
);
