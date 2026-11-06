import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

/// The phone's photos, videos and audio. Android and iOS only; tests swap in a
/// fake.
final mediaLibraryProvider = Provider<MediaLibrary>(
  (ref) =>
      Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')
      ? const PhoneMediaLibrary()
      : const NoMediaLibrary(),
);

/// The chat a system picker or camera was opened from. Android may close
/// Serafim while one is open on a low-memory phone; this is how the choice
/// still finds its way back.
class PickTarget {
  const PickTarget({
    required this.account,
    required this.recipientId,
    required this.contactName,
    this.groupId,
    this.username,
    this.profilePic,
    this.isGroup = false,
  });

  final String account;
  final String recipientId;
  final String contactName;
  final String? groupId;
  final String? username;
  final String? profilePic;
  final bool isGroup;

  String encode() => [
    account,
    recipientId,
    contactName,
    groupId ?? '',
    username ?? '',
    profilePic ?? '',
    isGroup ? '1' : '0',
  ].join('\u0001');

  static PickTarget? decode(String? raw) {
    final p = raw?.split('\u0001');
    if (p == null || p.length != 7) return null;
    return PickTarget(
      account: p[0],
      recipientId: p[1],
      contactName: p[2],
      groupId: p[3].isEmpty ? null : p[3],
      username: p[4].isEmpty ? null : p[4],
      profilePic: p[5].isEmpty ? null : p[5],
      isGroup: p[6] == '1',
    );
  }
}

/// Remembers where a pick is going for as long as it is open.
class PickTargetStore {
  PickTargetStore(this._ref);
  final Ref _ref;
  static const _key = 'pick.target';

  void remember(PickTarget target) =>
      _ref.read(sharedPreferencesProvider).setString(_key, target.encode());

  void forget() => _ref.read(sharedPreferencesProvider).remove(_key);

  PickTarget? get current =>
      PickTarget.decode(_ref.read(sharedPreferencesProvider).getString(_key));
}

final pickTargetStoreProvider = Provider<PickTargetStore>(PickTargetStore.new);

/// What a system picker handed back after Android closed the app, if anything.
final lostPickSourceProvider = Provider<Future<List<XFile>> Function()>((ref) {
  return () async {
    if (!Platform.isAndroid ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return const [];
    }
    final lost = await ImagePicker().retrieveLostData();
    return lost.files ?? const [];
  };
});

/// A pick that was lost, and the chat it belongs in. Android's copy is handed
/// over once, so this is read at most once per start. Null if there is none,
/// or it belongs to another account.
Future<({PickTarget target, List<XFile> files})?> recoverLostPick(
  Ref ref,
) async {
  final store = ref.read(pickTargetStoreProvider);
  final target = store.current;
  store.forget();
  // Always asked, so one left by another screen never lands in a chat later.
  final files = await ref.read(lostPickSourceProvider)();
  if (target == null ||
      files.isEmpty ||
      target.account != ref.read(currentAccountIdProvider)) {
    return null;
  }
  return (target: target, files: files);
}

final lostPickProvider =
    FutureProvider<({PickTarget target, List<XFile> files})?>(recoverLostPick);
