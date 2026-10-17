import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/services/group_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

final groupServiceProvider = Provider<GroupService>(
  (ref) => GroupService(ref.watch(apiDioProvider)),
);

/// The groups you are in. Opens from the copy saved on the phone and
/// refreshes from the server behind it, like the friends list.
class MyGroupsController extends AsyncNotifier<List<GroupSummary>> {
  @override
  Future<List<GroupSummary>> build() async {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const [];
    final saved = ref.read(localCacheProvider).groups(account);
    if (saved != null) {
      Future.microtask(() => _refresh(account));
      return saved;
    }
    return _fetch(account);
  }

  Future<List<GroupSummary>> _fetch(String account) async {
    final groups = await ref.read(groupServiceProvider).mine();
    await ref.read(localCacheProvider).saveGroups(account, groups);
    return groups;
  }

  Future<void> _refresh(String account) async {
    try {
      final fresh = await _fetch(account);
      if (ref.mounted && ref.read(currentAccountIdProvider) == account) {
        state = AsyncData(fresh);
      }
    } catch (_) {
      // Offline: keep the saved list.
    }
  }

  /// Re-reads from the server (after a change, or a `group_update`).
  Future<void> reload() async {
    final account = ref.read(currentAccountIdProvider);
    if (account != null) await _refresh(account);
  }
}

final myGroupsProvider =
    AsyncNotifierProvider<MyGroupsController, List<GroupSummary>>(
      MyGroupsController.new,
    );

/// One of your groups by id, from the list (null if you're not in it).
final myGroupProvider = Provider.family<GroupSummary?, String>((ref, id) {
  final groups = ref.watch(myGroupsProvider).value ?? const <GroupSummary>[];
  for (final g in groups) {
    if (g.id == id) return g;
  }
  return null;
});

/// Members, roles and rules. Fails (404) once you are no longer a member.
final groupDetailProvider = FutureProvider.autoDispose
    .family<GroupDetail, String>(
      (ref, id) => ref.watch(groupServiceProvider).detail(id),
    );

/// Member names by user id, for labelling messages in a group chat.
final groupMemberNamesProvider = Provider.autoDispose
    .family<Map<String, String>, String>((ref, id) {
      final detail = ref.watch(groupDetailProvider(id)).value;
      if (detail == null) return const {};
      return {for (final m in detail.members) m.user.id: m.user.displayName};
    });

/// When you last acknowledged each group's rules (so new or changed rules are
/// shown once).
class RulesSeenNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account == null) return const {};
    return ref.read(localCacheProvider).rulesSeen(account);
  }

  void acknowledge(String groupId, DateTime rulesUpdatedAt) {
    final account = ref.read(currentAccountIdProvider);
    if (account == null) return;
    state = {...state, groupId: rulesUpdatedAt};
    ref.read(localCacheProvider).saveRulesSeen(account, state);
  }
}

final rulesSeenProvider =
    NotifierProvider<RulesSeenNotifier, Map<String, DateTime>>(
      RulesSeenNotifier.new,
    );

/// Whether [group]'s rules should be shown to you now: there are rules and
/// you haven't acknowledged this version yet.
bool shouldShowRules(GroupSummary group, Map<String, DateTime> seen) {
  final updated = group.rulesUpdatedAt;
  if (updated == null) return false;
  final at = seen[group.id];
  return at == null || at.isBefore(updated);
}

/// Group commands. Each returns null (or results) on success and a message to
/// show on failure, and refreshes what changed.
class GroupActions {
  GroupActions(this._ref);

  final Ref _ref;

  GroupService get _service => _ref.read(groupServiceProvider);

  void _refresh(String groupId) {
    _ref.invalidate(groupDetailProvider(groupId));
    _ref.read(myGroupsProvider.notifier).reload();
  }

  /// Creates a group, then sets its photo (the path needs the group id). A
  /// failed photo upload doesn't undo the group.
  Future<({GroupDetail? group, List<AddResult> results, String? error})>
  create({
    required String name,
    String? rules,
    List<String> memberIds = const [],
    Uint8List? photo,
  }) async {
    try {
      final created = await _service.create(
        name: name,
        rules: rules,
        memberIds: memberIds,
      );
      final group = created.group;
      String? photoError;
      if (photo != null) {
        photoError = await changePhoto(group.id, photo);
      }
      await _ref.read(myGroupsProvider.notifier).reload();
      return (group: group, results: created.results, error: photoError);
    } catch (error) {
      return (
        group: null,
        results: const <AddResult>[],
        error: humanError(error, fallback: "Couldn't create the group."),
      );
    }
  }

  Future<({List<AddResult> results, String? error})> addMembers(
    String groupId, {
    List<String> userIds = const [],
    List<String> usernames = const [],
  }) async {
    try {
      final results = await _service.addMembers(
        groupId,
        userIds: userIds,
        usernames: usernames,
      );
      _refresh(groupId);
      return (results: results, error: null);
    } catch (error) {
      return (
        results: const <AddResult>[],
        error: humanError(error, fallback: "Couldn't add them."),
      );
    }
  }

  Future<String?> updateInfo(String groupId, {String? name, String? rules}) =>
      _run(groupId, () => _service.update(groupId, name: name, rules: rules));

  Future<String?> changePhoto(String groupId, Uint8List jpeg) async {
    final account = _ref.read(currentAccountIdProvider);
    if (account == null) return 'You are signed out.';
    return _run(groupId, () async {
      final url = await _ref
          .read(avatarStorageServiceProvider)
          .uploadGroupPhoto(account, groupId, jpeg);
      return _service.update(groupId, photoUrl: url);
    });
  }

  Future<String?> removeMember(String groupId, String userId) =>
      _run(groupId, () => _service.removeMember(groupId, userId));

  Future<String?> setRole(String groupId, String userId, GroupRole role) =>
      _run(groupId, () => _service.setRole(groupId, userId, role));

  Future<String?> transfer(String groupId, String userId) =>
      _run(groupId, () => _service.transfer(groupId, userId));

  /// Leaves; the group's messages are removed from this device.
  Future<String?> leave(String groupId, {String? newOwnerId}) async {
    final error = await _run(
      groupId,
      () => _service.leave(groupId, newOwnerId: newOwnerId),
    );
    if (error == null) await forget(_ref, groupId);
    return error;
  }

  /// Removes everything about a group you are no longer in from this device.
  static Future<void> forget(Ref ref, String groupId) async {
    await ref.read(isarServiceProvider).deleteRoom(groupRoomId(groupId));
    ref.invalidate(groupDetailProvider(groupId));
    await ref.read(myGroupsProvider.notifier).reload();
  }

  Future<String?> _run(
    String groupId,
    Future<Object?> Function() action,
  ) async {
    try {
      await action();
      _refresh(groupId);
      return null;
    } catch (error) {
      return humanError(error);
    }
  }
}

final groupActionsProvider = Provider<GroupActions>(GroupActions.new);
