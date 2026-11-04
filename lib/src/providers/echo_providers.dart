import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/echo.dart';
import 'package:serafim/src/data/services/echo_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final echoServiceProvider = Provider<EchoService>(
  (ref) => EchoService(ref.watch(apiDioProvider)),
);

/// Your latest Echo and the limits.
final myEchoProvider = FutureProvider<MyEchoStatus>((ref) async {
  if (ref.watch(currentAccountIdProvider) == null) return const MyEchoStatus();
  return ref.watch(echoServiceProvider).mine();
});

/// The latest Echo someone sent you, for the card an Echo notification
/// opens. Fetched fresh each time it is opened.
final echoFromProvider = FutureProvider.autoDispose.family<Echo, String>(
  (ref, userId) => ref.watch(echoServiceProvider).latestFrom(userId),
);

/// Sending, ending, answering and hiding Echos, keeping the lists fresh.
class EchoActions {
  const EchoActions(this._ref);

  final Ref _ref;

  EchoService get _service => _ref.read(echoServiceProvider);

  /// Sends an Echo and returns it (with how many it reached).
  Future<Echo> send({
    required String text,
    EchoAudience audience = EchoAudience.everyone,
    String? tag,
  }) async {
    final echo = await _service.send(text: text, audience: audience, tag: tag);
    _ref.invalidate(myEchoProvider);
    return echo;
  }

  Future<void> close(String id) async {
    await _service.close(id);
    _ref.invalidate(myEchoProvider);
  }

  /// Returns the id of the person to chat with.
  Future<String> respond(String id) => _service.respond(id);

  Future<void> hide(String userId) => _service.hide(userId);
}

final echoActionsProvider = Provider<EchoActions>(EchoActions.new);
