import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';

/// The chat list must have everything on the phone on its FIRST build — no
/// empty list that fills in a moment later.
void main() {
  late Directory dir;
  late Isar isar;
  late bool haveLib;

  setUpAll(() async {
    final libPath =
        '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
        'isar_community_flutter_libs-3.3.2/linux/libisar.so';
    haveLib = File(libPath).existsSync();
    if (!haveLib) return;
    await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
    dir = Directory.systemTemp.createTempSync('serafim_instant');
    isar = await Isar.open(
      [LocalMessageSchema, LocalChatRoomSchema],
      directory: dir.path,
    );
    await isar.writeTxn(() async {
      await isar.localChatRooms.putAll([
        LocalChatRoom()
          ..roomId = 'me_a'
          ..peerUserId = 'a'
          ..lastMessageText = 'older'
          ..lastMessageTimestamp = DateTime.utc(2026, 1, 1),
        LocalChatRoom()
          ..roomId = 'b_me'
          ..peerUserId = 'b'
          ..lastMessageText = 'newer'
          ..unreadCount = 3
          ..lastMessageTimestamp = DateTime.utc(2026, 2, 1),
      ]);
      await isar.localMessages.put(
        LocalMessage()
          ..messageId = 'm1'
          ..roomId = 'b_me'
          ..senderId = 'b'
          ..recipientId = 'me'
          ..timestamp = DateTime.utc(2026, 2, 1),
      );
    });
  });

  tearDownAll(() async {
    if (!haveLib) return;
    await isar.close();
    dir.deleteSync(recursive: true);
  });

  test('the service reads rooms and peers synchronously, newest first', () {
    if (!haveLib) return;
    final service = IsarService.withDb(Future.value(isar));
    expect(service.roomsNow().map((r) => r.roomId), ['b_me', 'me_a']);
    expect(service.peerIdsNow('me'), ['b']);
  });

  test('the providers have the data on the very first read', () {
    if (!haveLib) return;
    final service = IsarService.withDb(Future.value(isar));
    final container = ProviderContainer(
      overrides: [
        preopenedIsarProvider.overrideWithValue(service),
        // Signed out here, so no background rebuild runs under the test.
        currentAccountIdProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    // No await, no pump: this is the first frame's view of the world.
    final rooms = container.read(chatRoomsProvider);
    expect(rooms.map((r) => r.roomId), ['b_me', 'me_a']);

    final previews = container.read(roomPreviewsProvider);
    expect(previews['b_me']?.text, 'newer');
    expect(previews['b_me']?.unread, 3);
  });
}
