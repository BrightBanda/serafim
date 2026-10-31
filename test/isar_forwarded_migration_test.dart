import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';

import 'old_message_schema.dart';

/// What happens to the messages already on a phone when a new field is
/// added to [LocalMessage].
///
/// The generator gives each property an id based on its place in the
/// alphabetical list of names, so adding `forwarded` (which sorts between
/// `editedAt` and `groupId`) shifts the id of every property after it. If
/// the migration matches properties by id, `groupId` would be renamed to
/// `forwarded` and every group message on the phone would lose its group.
/// (`fileName` and `fileSize`, for videos and audio files, shifted them
/// again; the same holds.)
///
/// These tests open a database with the old layout, write a message, and
/// then open it with the new one.
void main() {
  late Directory dir;
  late bool haveLib;

  setUpAll(() async {
    // Isar's native library ships inside the flutter_libs package; tests load
    // it from the pub cache (Linux).
    final libPath =
        '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
        'isar_community_flutter_libs-3.3.2/linux/libisar.so';
    haveLib = File(libPath).existsSync();
    if (haveLib) {
      await Isar.initializeIsarCore(libraries: {Abi.current(): libPath});
    }
    dir = Directory.systemTemp.createTempSync('serafim_migrate');
  });

  tearDownAll(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the old layout is what we think it is', () {
    // If this ever stops being true the test below is testing nothing.
    expect(
      OldLocalMessageSchema.properties['groupId']!.id,
      2,
      reason: 'groupId used to be id 2',
    );
    final nowAt2 = LocalMessageSchema.properties.entries
        .singleWhere((e) => e.value.id == 2)
        .key;
    expect(
      nowAt2,
      isNot('groupId'),
      reason: 'a newer field now takes id 2',
    );
    expect(
      LocalMessageSchema.properties['groupId']!.id,
      greaterThan(2),
      reason: 'groupId moved',
    );
  });

  test('a message written before the change survives it', () async {
    if (!haveLib) {
      markTestSkipped('libisar.so not found in the pub cache');
    }

    // Write with the old layout.
    var isar = await Isar.open(
      [OldLocalMessageSchema],
      directory: dir.path,
      name: 'before',
    );
    final msg = LocalMessage()
      ..messageId = 'm1'
      ..roomId = 'room_1'
      ..senderId = 'me'
      ..recipientId = 'them'
      ..groupId = 'g1'
      ..textContent = 'hello'
      ..timestamp = DateTime.utc(2026);
    await isar.writeTxn(() => isar.localMessages.put(msg));
    await isar.close();

    // Read with the new layout.
    isar = await Isar.open(
      [LocalMessageSchema],
      directory: dir.path,
      name: 'before',
    );
    final after = await isar.localMessages.getByMessageId('m1');
    await isar.close();

    expect(after, isNotNull);
    expect(after!.textContent, 'hello');
    expect(
      after.groupId,
      'g1',
      reason: 'the group id must survive the migration',
    );
    expect(after.forwarded, isFalse);
    expect(after.type, MessageType.text);
    expect(after.fileName, isNull);
    expect(after.fileSize, isNull);
  });
}
