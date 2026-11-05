import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/nickname_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final nicknameServiceProvider = Provider<NicknameService>(
  (ref) => NicknameService(ref.watch(apiDioProvider)),
);

/// Your nicknames for friends, and theirs for you. Refreshed when a friend
/// changes theirs (`nickname_update` over the socket).
final nicknamesProvider = FutureProvider<Nicknames>((ref) async {
  if (ref.watch(currentAccountIdProvider) == null) return const Nicknames();
  return ref.watch(nicknameServiceProvider).get();
});

/// What you call [userId], or null when you haven't given them a nickname.
final nicknameForProvider = Provider.family<String?, String>(
  (ref, userId) => ref.watch(nicknamesProvider).value?.given[userId],
);

/// What [userId] calls you, or null.
final nicknameFromProvider = Provider.family<String?, String>(
  (ref, userId) => ref.watch(nicknamesProvider).value?.received[userId],
);
