import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/data/services/circle_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';

final circleServiceProvider = Provider<CircleService>(
  (ref) => CircleService(ref.watch(apiDioProvider)),
);

/// The Circles the signed-in person has joined.
final myCirclesProvider = FutureProvider<List<CircleSummary>>((ref) async {
  if (ref.watch(currentAccountIdProvider) == null) return const [];
  return ref.watch(circleServiceProvider).mine();
});

/// One of your Circles by id, from the list (null if you are not in it).
final myCircleProvider = Provider.family<CircleSummary?, String>((ref, id) {
  final circles = ref.watch(myCirclesProvider).value ?? const <CircleSummary>[];
  for (final c in circles) {
    if (c.id == id) return c;
  }
  return null;
});

/// Circles to look at. [section] is `for_you` or `popular`.
final discoverCirclesProvider =
    FutureProvider.family<List<CircleSummary>, DiscoverCirclesQuery>((
      ref,
      query,
    ) async {
      if (ref.watch(currentAccountIdProvider) == null) return const [];
      return ref
          .watch(circleServiceProvider)
          .discover(
            section: query.section,
            category: query.category,
            query: query.query,
          );
    });

/// What to show in the Circles tab.
class DiscoverCirclesQuery {
  const DiscoverCirclesQuery({
    this.section = 'for_you',
    this.category,
    this.query = '',
  });

  final String section;
  final String? category;
  final String query;

  bool get isSearching => query.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is DiscoverCirclesQuery &&
      other.section == section &&
      other.category == category &&
      other.query == query;

  @override
  int get hashCode => Object.hash(section, category, query);
}

/// One Circle in full: its details, members and pending requests.
///
/// Fails with 404 once you are no longer a member of a private Circle, and
/// 403 when you cannot see its posts.
final circleDetailProvider = FutureProvider.family<CircleDetail, String>((
  ref,
  id,
) async {
  return ref.watch(circleServiceProvider).detail(id);
});

/// The people waiting to join a Circle. Owners and Overseers only.
final circleRequestsProvider =
    FutureProvider.family<List<CircleJoinRequest>, String>((ref, id) async {
      return ref.watch(circleServiceProvider).requests(id);
    });

/// Joins a Circle, or asks to join a private one, then refreshes the lists
/// the answer changes.
class CircleJoinController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> join(String circleId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(circleServiceProvider).join(circleId);
      ref.invalidate(myCirclesProvider);
      ref.invalidate(discoverCirclesProvider);
      ref.invalidate(circleDetailProvider(circleId));
    });
  }
}

final circleJoinProvider = AsyncNotifierProvider<CircleJoinController, void>(
  CircleJoinController.new,
);

/// Leaves a Circle.
class CircleLeaveController extends AsyncNotifier<CircleLeaveResult?> {
  @override
  Future<CircleLeaveResult?> build() async => null;

  Future<CircleLeaveResult?> leave(String circleId) async {
    final result = await ref.read(circleServiceProvider).leave(circleId);
    ref.invalidate(myCirclesProvider);
    ref.invalidate(discoverCirclesProvider);
    ref.invalidate(circleDetailProvider(circleId));
    state = AsyncData(result);
    return result;
  }
}

final circleLeaveProvider =
    AsyncNotifierProvider<CircleLeaveController, CircleLeaveResult?>(
      CircleLeaveController.new,
    );

/// Answers a request to join: approved or rejected.
class CircleRequestController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> approve(String circleId, String requestId) =>
      _answer(circleId, requestId, approve: true);

  Future<void> reject(String circleId, String requestId) =>
      _answer(circleId, requestId, approve: false);

  Future<void> _answer(
    String circleId,
    String requestId, {
    required bool approve,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(circleServiceProvider);
      if (approve) {
        await service.approve(circleId, requestId);
      } else {
        await service.reject(circleId, requestId);
      }
      ref.invalidate(circleRequestsProvider(circleId));
      ref.invalidate(circleDetailProvider(circleId));
    });
  }
}

final circleRequestProvider =
    AsyncNotifierProvider<CircleRequestController, void>(
      CircleRequestController.new,
    );

/// The actions an Owner or Overseer can take on a member: change their
/// role, remove them, ban them, or hand the Circle over.
class CircleMemberController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> setRole(String circleId, String userId, CircleRole role) => _run(
    circleId,
    () => ref.read(circleServiceProvider).setRole(circleId, userId, role),
  );

  Future<void> remove(String circleId, String userId) => _run(
    circleId,
    () => ref.read(circleServiceProvider).removeMember(circleId, userId),
  );

  Future<void> ban(String circleId, String userId, {String? reason}) => _run(
    circleId,
    () => ref.read(circleServiceProvider).ban(circleId, userId, reason: reason),
  );

  Future<void> transfer(String circleId, String userId) => _run(
    circleId,
    () => ref.read(circleServiceProvider).transfer(circleId, userId),
  );

  Future<void> _run(String circleId, Future<Object?> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await action();
      ref.invalidate(circleDetailProvider(circleId));
      ref.invalidate(myCirclesProvider);
    });
  }
}

final circleMemberProvider =
    AsyncNotifierProvider<CircleMemberController, void>(
      CircleMemberController.new,
    );

/// Mutes a Circle, or changes which notifications it sends.
class CircleSettingsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> setMuted(String circleId, bool muted) => _run(
    circleId,
    () => ref
        .read(circleServiceProvider)
        .notificationSettings(circleId, muted: muted),
  );

  Future<void> _run(String circleId, Future<Object?> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      ref.invalidate(circleDetailProvider(circleId));
    });
  }
}

final circleSettingsProvider =
    AsyncNotifierProvider<CircleSettingsController, void>(
      CircleSettingsController.new,
    );
