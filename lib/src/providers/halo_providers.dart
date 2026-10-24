import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';

/// Halo: a light a person can turn on for a while to tell their friends they
/// are free to chat. Off by default; nothing about presence is shown unless
/// someone chooses to. Only friends are told, and it switches itself off.

/// What a friend's halo was last said to be over the live connection (a
/// `halo` event). Absent means "no news, use what the list said"; an old time
/// means they put it out.
class FriendHalos extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() => const {};

  /// The server's `halo` event: `{user_id, halo_until | null}`.
  void heard(Map<String, dynamic> event) {
    final id = event['user_id'] as String?;
    if (id == null) return;
    final raw = event['halo_until'];
    final until = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    state = {...state, id: until ?? DateTime.fromMillisecondsSinceEpoch(0)};
  }
}

final friendHaloProvider = NotifierProvider<FriendHalos, Map<String, DateTime>>(
  FriendHalos.new,
);

/// Whether [key]'s halo is lit right now. Rebuilds itself at the exact moment
/// it runs out, so a light goes off on screen without any polling.
///
/// The key is the friend's id and what their list entry said; a live event
/// from [friendHaloProvider] wins over the list.
final haloLitProvider = Provider.autoDispose
    .family<bool, ({String id, DateTime? until})>((ref, key) {
      final live = ref.watch(friendHaloProvider.select((m) => m[key.id]));
      return _litUntil(ref, live ?? key.until);
    });

/// Convenience for a [PublicUser].
({String id, DateTime? until}) haloKey(PublicUser user) =>
    (id: user.id, until: user.haloUntil);

bool _litUntil(Ref ref, DateTime? until) {
  if (until == null) return false;
  final left = until.difference(DateTime.now().toUtc());
  if (left <= Duration.zero) return false;
  final timer = Timer(left, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return true;
}

/// Whether your halo was last lit for Wings only (so the control can start
/// from the same choice).
final myHaloAudienceProvider = Provider<bool>(
  (ref) => ref.watch(
    profileViewModelProvider.select((p) => p.value?.haloAudience == 'wings'),
  ),
);

/// Your own halo: lit or not, and the controls.
class MyHalo extends Notifier<DateTime?> {
  @override
  DateTime? build() =>
      ref.watch(profileViewModelProvider.select((p) => p.value?.haloUntil));

  /// Lights it for [minutes]. Throws if the server refuses.
  Future<void> light(int minutes, {bool wingsOnly = false}) async {
    state = await ref
        .read(profileServiceProvider)
        .lightHalo(minutes, wingsOnly: wingsOnly);
  }

  /// Puts it out. Throws if the server refuses.
  Future<void> dim() async {
    await ref.read(profileServiceProvider).dimHalo();
    state = null;
  }
}

final myHaloProvider = NotifierProvider<MyHalo, DateTime?>(MyHalo.new);

/// Whether your own halo is lit now (and drops back to off by itself).
final myHaloLitProvider = Provider.autoDispose<bool>(
  (ref) => _litUntil(ref, ref.watch(myHaloProvider)),
);
