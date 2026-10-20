import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/chat_filter.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

/// The custom chat filters the person made.
///
/// The built-in filters (All, Friends, Unread, Groups) are constants and are
/// not stored; only the custom ones are.
class ChatFiltersNotifier extends Notifier<List<ChatFilter>> {
  @override
  List<ChatFilter> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    return ref.read(localCacheProvider).chatFilters(account) ?? const [];
  }

  /// Adds a filter and returns it, so the caller can select it.
  ChatFilter add(String name, Set<String> roomIds) {
    final filter = ChatFilter(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      kind: ChatFilterKind.custom,
      roomIds: roomIds,
    );
    state = [...state, filter];
    _save();
    return filter;
  }

  void rename(String id, String name) {
    state = [
      for (final f in state)
        if (f.id == id) f.copyWith(name: name) else f,
    ];
    _save();
  }

  void remove(String id) {
    state = [for (final f in state) if (f.id != id) f];
    _save();
  }

  void setRooms(String id, Set<String> roomIds) {
    state = [
      for (final f in state)
        if (f.id == id) f.copyWith(roomIds: roomIds) else f,
    ];
    _save();
  }

  void _save() {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    ref.read(localCacheProvider).saveChatFilters(account, state);
  }
}

final chatFiltersProvider =
    NotifierProvider<ChatFiltersNotifier, List<ChatFilter>>(
      ChatFiltersNotifier.new,
    );

/// Which filter is showing. Session-only: it is not worth remembering, and
/// the person expects the list to be where they left it next time.
class SelectedChatFilterNotifier extends Notifier<String> {
  @override
  String build() => ChatFilter.all.id;

  void select(String id) => state = id;
}

final selectedChatFilterProvider =
    NotifierProvider<SelectedChatFilterNotifier, String>(
      SelectedChatFilterNotifier.new,
    );

/// The filter that is showing, from the built-ins and the custom ones.
final activeChatFilterProvider = Provider<ChatFilter>((ref) {
  final id = ref.watch(selectedChatFilterProvider);
  final custom = ref.watch(chatFiltersProvider);
  for (final f in ChatFilter.builtIns) {
    if (f.id == id) return f;
  }
  for (final f in custom) {
    if (f.id == id) return f;
  }
  return ChatFilter.all;
});
