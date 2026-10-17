import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';

/// Stickers this account sent recently, newest first (kept on the device).
class RecentStickersNotifier extends Notifier<List<String>> {
  static const max = 16;

  @override
  List<String> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    // Drop ids this version of the app no longer has.
    return ref
        .read(localCacheProvider)
        .recentStickers(account)
        .where((id) => stickerById(id) != null)
        .toList();
  }

  void used(String id) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    state = [id, ...state.where((s) => s != id)].take(max).toList();
    ref.read(localCacheProvider).saveRecentStickers(account, state);
  }
}

final recentStickersProvider =
    NotifierProvider<RecentStickersNotifier, List<String>>(
      RecentStickersNotifier.new,
    );
