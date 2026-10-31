import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/local/saved_media_store.dart';
import 'package:serafim/src/data/models/sticker_collection.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/sticker_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('the stored shape', () {
    test('stickers and files round-trip; nothing large is stored', () {
      final c = StickerCollection(
        id: 'c1',
        name: 'Faves',
        createdAt: DateTime.utc(2026),
        items: const [
          StickerCollectionItem.sticker('doodles/frog', name: 'Frog'),
          StickerCollectionItem.media(
            kind: StickerCollectionItemKind.video,
            file: 'abc.mp4',
            name: 'holiday.mp4',
          ),
        ],
      );
      final json = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      final back = StickerCollection.fromJson(json);
      expect(back.items.map((i) => i.key), [
        'sticker:doodles/frog',
        'file:abc.mp4',
      ]);
      expect(back.items.last.isVideo, isTrue);
      expect(back.items.last.name, 'holiday.mp4');
      expect(back.stickerIds, ['doodles/frog']);
      expect(jsonEncode(json), isNot(contains('bytes')));
    });

    test("an older version's inline GIF is read for migration", () {
      final item = StickerCollectionItem.fromJson({
        'kind': 'gif',
        'sticker_id': '',
        'name': 'dance',
        'gif_bytes': base64Encode([0x47, 0x49, 0x46, 0x38]),
      });
      expect(item!.needsMigration, isTrue);
      expect(item.isGif, isTrue);
    });

    test('entries this version cannot use are dropped, not crashed on', () {
      final c = StickerCollection.fromJson({
        'id': 'c1',
        'name': 'x',
        'created_at': 'not a date',
        'items': [
          {'kind': 'hologram'},
          {'kind': 'sticker'},
          {'kind': 'video'},
          'junk',
          {'kind': 'sticker', 'sticker_id': 'doodles/cat'},
        ],
      });
      expect(c.items.map((i) => i.key), ['sticker:doodles/cat']);
    });
  });

  group('saving and removing', () {
    late Directory dir;
    late ProviderContainer c;
    late SharedPreferences prefs;

    Future<ProviderContainer> start([
      Map<String, Object> initial = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initial);
      prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localCacheProvider.overrideWithValue(LocalCache(prefs)),
          currentAccountIdProvider.overrideWithValue('me'),
          savedMediaStoreProvider.overrideWithValue(
            SavedMediaStore(baseDir: () async => dir),
          ),
        ],
      );
    }

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('collections');
      c = await start();
    });
    tearDown(() {
      c.dispose();
      dir.deleteSync(recursive: true);
    });

    File source(String name, List<int> bytes) =>
        File('${dir.path}/$name')..writeAsBytesSync(bytes);

    List<String> savedFiles() {
      final d = Directory('${dir.path}/saved_media/me');
      if (!d.existsSync()) return const [];
      return [for (final f in d.listSync()) f.uri.pathSegments.last]..sort();
    }

    test('a file is copied only once a collection is chosen', () async {
      final n = c.read(stickerCollectionsProvider.notifier);
      final a = n.createCollection('A');
      final video = source('clip.mp4', [1, 2, 3]);

      final pending = await n.prepareFile(
        video.path,
        StickerCollectionItemKind.video,
        name: 'clip.mp4',
      );
      expect(savedFiles(), isEmpty);

      expect(await n.add(a.id, pending), isTrue);
      expect(savedFiles(), [pending.item.file]);
      expect(pending.item.file, endsWith('.mp4'));
      // The picked file is untouched.
      expect(video.existsSync(), isTrue);
      final path = await n.pathOf(
        c.read(stickerCollectionsProvider).single.items.single,
      );
      expect(File(path!).readAsBytesSync(), [1, 2, 3]);
    });

    test('the same contents are one item, stored once', () async {
      final n = c.read(stickerCollectionsProvider.notifier);
      final a = n.createCollection('A');
      final b = n.createCollection('B');
      final first = await n.prepareFile(
        source('one.gif', [7, 7, 7]).path,
        StickerCollectionItemKind.gif,
      );
      final sameAgain = await n.prepareFile(
        source('renamed.gif', [7, 7, 7]).path,
        StickerCollectionItemKind.gif,
      );
      expect(sameAgain.item.key, first.item.key);

      expect(await n.add(a.id, first), isTrue);
      expect(await n.add(a.id, sameAgain), isFalse); // already there
      expect(await n.add(b.id, sameAgain), isTrue);
      expect(savedFiles().length, 1);
    });

    test('the file goes when the last collection lets go of it', () async {
      final n = c.read(stickerCollectionsProvider.notifier);
      final a = n.createCollection('A');
      final b = n.createCollection('B');
      final pending = await n.prepareFile(
        source('song.mp3', [5]).path,
        StickerCollectionItemKind.audio,
      );
      await n.add(a.id, pending);
      await n.add(b.id, pending);

      expect(await n.remove(pending.item.key, collectionId: a.id), 1);
      expect(savedFiles(), isNotEmpty); // B still has it
      expect(await n.remove(pending.item.key), 1);
      expect(savedFiles(), isEmpty);
      expect(
        c.read(stickerCollectionsProvider).every((x) => x.isEmpty),
        isTrue,
      );
    });

    test('stickers save by id, and survive a restart', () async {
      final n = c.read(stickerCollectionsProvider.notifier);
      await n.addToNew('Frogs', PendingCollectionItem.sticker('doodles/frog'));
      expect(n.nameTaken('frogs'), isTrue);

      final again = await start({
        for (final k in prefs.getKeys()) k: prefs.get(k)!,
      });
      addTearDown(again.dispose);
      final restored = again.read(stickerCollectionsProvider).single;
      expect(restored.name, 'Frogs');
      expect(restored.stickerIds, ['doodles/frog']);
    });

    test("an older version's inline GIFs move to files once", () async {
      final gif = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2];
      LocalCache(prefs).saveStickerCollections('me', [
        StickerCollection.fromJson({
          'id': 'c1',
          'name': 'Old',
          'created_at': '2026-01-01T00:00:00Z',
          'items': [
            {
              'kind': 'gif',
              'sticker_id': '',
              'name': 'dance',
              'gif_bytes': base64Encode(gif),
            },
            {'kind': 'sticker', 'sticker_id': 'doodles/frog'},
          ],
        }),
      ]);
      final migrated = await start({
        for (final k in prefs.getKeys()) k: prefs.get(k)!,
      });
      addTearDown(migrated.dispose);
      migrated.read(stickerCollectionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final items = migrated.read(stickerCollectionsProvider).single.items;
      expect(items.first.isGif, isTrue);
      expect(items.first.needsMigration, isFalse);
      expect(items.first.name, 'dance');
      expect(items.first.file, endsWith('.gif'));
      expect(items.last.key, 'sticker:doodles/frog');
      final path = await migrated
          .read(stickerCollectionsProvider.notifier)
          .pathOf(items.first);
      expect(File(path!).readAsBytesSync(), gif);
      // The bytes are gone from preferences.
      final stored = prefs.getKeys().map((k) => '${prefs.get(k)}').join();
      expect(stored, isNot(contains('gif_bytes')));
    });
  });
}
