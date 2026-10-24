import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/wings_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

/// How many Wings a person can have. Seraphim have six wings; the small
/// number is the point. (The server enforces it too.)
const int maxWings = 6;

final wingsServiceProvider = Provider<WingsService>(
  (ref) => WingsService(ref.watch(apiDioProvider)),
);

/// Your Wings: up to six closest friends. Private to you — they are not told.
///
/// Opens at once from the copy saved on the phone, then checks the server in
/// the background, like the friends list does.
class WingsNotifier extends Notifier<List<PublicUser>> {
  @override
  List<PublicUser> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    final saved = ref.read(localCacheProvider).wings(account);
    Future.microtask(() => _refresh(account));
    return saved ?? const [];
  }

  WingsService get _service => ref.read(wingsServiceProvider);

  Future<void> _refresh(String account) async {
    try {
      final fresh = await _service.list();
      if (!ref.mounted || ref.read(currentAccountIdProvider) != account) return;
      _keep(account, fresh);
    } catch (_) {
      // Offline: keep what is on the phone.
    }
  }

  void _keep(String account, List<PublicUser> wings) {
    state = wings;
    ref.read(localCacheProvider).saveWings(account, wings);
  }

  bool get isFull => state.length >= maxWings;

  /// Makes [user] one of your Wings, showing it at once. Returns null on
  /// success, or a message to show; on failure the list goes back.
  Future<String?> add(PublicUser user) async {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return 'Sign in first.';
    if (state.any((w) => w.id == user.id)) return null;
    if (isFull) return 'You can have up to $maxWings Wings. Remove one first.';
    final before = state;
    state = [...state, user];
    try {
      _keep(account, await _service.add(user.id));
      return null;
    } catch (error) {
      if (ref.mounted) state = before;
      return humanError(error);
    }
  }

  /// Takes [userId] off your Wings. Returns null, or a message.
  Future<String?> remove(String userId) async {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return 'Sign in first.';
    final before = state;
    state = [
      for (final w in state)
        if (w.id != userId) w,
    ];
    try {
      _keep(account, await _service.remove(userId));
      return null;
    } catch (error) {
      if (ref.mounted) state = before;
      return humanError(error);
    }
  }
}

final wingsProvider = NotifierProvider<WingsNotifier, List<PublicUser>>(
  WingsNotifier.new,
);

/// The ids of your Wings.
final wingIdsProvider = Provider<Set<String>>(
  (ref) => {for (final w in ref.watch(wingsProvider)) w.id},
);

/// Whether [userId] is one of your Wings. Rebuilds only when that changes.
final isWingProvider = Provider.family<bool, String>(
  (ref, userId) =>
      ref.watch(wingIdsProvider.select((ids) => ids.contains(userId))),
);
