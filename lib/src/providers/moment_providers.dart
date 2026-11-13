import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/core/config/feature_flags.dart';
import 'package:serafim/src/data/models/moment.dart';
import 'package:serafim/src/data/services/moment_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final momentServiceProvider = Provider<MomentService>(
  (ref) => MomentService(ref.watch(apiDioProvider)),
);

/// Who has a moment showing, by user id: what the coloured ring round a
/// picture reads. Screens that show people ask for theirs with [refresh]
/// (one request for all of them), and the rings update everywhere.
class MomentRingsNotifier extends Notifier<Map<String, MomentRing>> {
  @override
  Map<String, MomentRing> build() {
    // Another account's rings are none of this one's business.
    ref.watch(currentAccountIdProvider);
    ref.onDispose(() => _timer?.cancel());
    _asked.clear();
    _pending.clear();
    return const {};
  }

  final Map<String, DateTime> _asked = {};
  final Set<String> _pending = {};
  Timer? _timer;

  /// How long a lookup is trusted before the same person is asked about again.
  static const _fresh = Duration(minutes: 2);

  /// An avatar asks for its person's ring. Asks made in the same moment go
  /// out as one request, and the same person is not asked about again soon.
  void request(String userId, {DateTime? now}) {
    if (!FeatureFlags.moments) return;
    final at = now ?? DateTime.now();
    final last = _asked[userId];
    if (last != null && at.difference(last) < _fresh) return;
    _asked[userId] = at;
    _pending.add(userId);
    _timer ??= Timer(const Duration(milliseconds: 60), () {
      _timer = null;
      final ids = _pending.toList();
      _pending.clear();
      unawaited(refresh(ids));
    });
  }

  /// Looks up [userIds] now. Whoever has nothing showing loses their ring.
  Future<void> refresh(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty || ref.read(currentAccountIdProvider) == null) return;
    try {
      final service = ref.read(momentServiceProvider);
      final found = <MomentRing>[];
      for (var i = 0; i < ids.length; i += 100) {
        found.addAll(await service.rings(ids.skip(i).take(100)));
      }
      final next = {...state}..removeWhere((id, _) => ids.contains(id));
      for (final ring in found) {
        next[ring.userId] = ring;
      }
      state = next;
    } catch (_) {
      // A ring is a nicety: not having it must never get in the way.
    }
  }

  /// Adds what a lookup found, without forgetting anyone else's ring.
  void merge(Iterable<MomentRing> rings) {
    state = {...state, for (final r in rings) r.userId: r};
  }

  /// You have just looked at everything [userId] has showing.
  void markSeen(String userId) {
    final ring = state[userId];
    if (ring == null || ring.allSeen) return;
    state = {...state, userId: ring.seen()};
  }
}

final momentRingsProvider =
    NotifierProvider<MomentRingsNotifier, Map<String, MomentRing>>(
      MomentRingsNotifier.new,
    );

/// Friends who have a moment showing, unseen first: the strip at the top of
/// the feed. Their rings are also put where avatars everywhere read them, so
/// looking at someone's moments quiets their ring in the strip too.
final friendMomentsProvider = FutureProvider.autoDispose<List<MomentRing>>((
  ref,
) async {
  if (ref.watch(currentAccountIdProvider) == null) return const [];
  final rings = await ref.watch(momentServiceProvider).feed();
  ref.read(momentRingsProvider.notifier).merge(rings);
  return rings;
});

/// [userId]'s moments you may see. Fetched fresh each time they are opened.
final userMomentsProvider = FutureProvider.autoDispose
    .family<List<Moment>, String>(
      (ref, userId) => ref.watch(momentServiceProvider).of(userId),
    );

/// Your own moments that are still showing.
final myMomentsProvider = FutureProvider.autoDispose<List<Moment>>((ref) {
  if (ref.watch(currentAccountIdProvider) == null) return const [];
  return ref.watch(momentServiceProvider).mine();
});

/// The picture of a photo moment.
final momentPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, id) => ref.watch(momentServiceProvider).photo(id),
    );

/// Looking at, liking and deleting moments, keeping the rings in step.
class MomentActions {
  const MomentActions(this._ref);

  final Ref _ref;

  MomentService get _service => _ref.read(momentServiceProvider);

  /// Records that you looked. Quiet: it never fails the viewer. With
  /// [private] (your read receipts are off) the owner is not told.
  Future<void> markSeen(Moment moment, {bool private = false}) async {
    if (moment.seen) return;
    try {
      await _service.markSeen(moment.id, private: private);
    } catch (_) {}
  }

  /// Saves a moment's picture or video to the gallery. Returns where it went.
  Future<String> save(Moment moment, {required String ownerLabel}) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/moment-${moment.id}.${moment.isVideo ? 'mp4' : 'jpg'}',
    );
    try {
      if (moment.isVideo) {
        final url = await _service.videoUrl(moment.id);
        await Dio().download(url, file.path);
      } else {
        await file.writeAsBytes(await _service.photo(moment.id));
      }
      final saver = _ref.read(attachmentDownloadServiceProvider);
      return moment.isVideo
          ? await saver.saveVideo(
              file.path,
              senderLabel: ownerLabel,
              sentAt: moment.createdAt,
            )
          : await saver.saveImage(
              file.path,
              senderLabel: ownerLabel,
              sentAt: moment.createdAt,
            );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<Moment> setLiked(Moment moment, bool liked) =>
      liked ? _service.like(moment.id) : _service.unlike(moment.id);

  Future<void> delete(Moment moment) async {
    await _service.delete(moment.id);
    _ref.invalidate(myMomentsProvider);
    unawaited(_ref.read(momentRingsProvider.notifier).refresh([moment.userId]));
  }
}

final momentActionsProvider = Provider<MomentActions>(MomentActions.new);
