import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/app_settings.dart';
import 'package:serafim/src/data/services/chat_media_store.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/sticker_providers.dart';
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/stickers/sticker_picker.dart';
import 'package:serafim/src/utils/stickers/sticker_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Must match the server's STICKER_RE (app/api/ws.py).
final serverStickerId = RegExp(r'^[a-z0-9_]{1,32}/[a-z0-9_]{1,32}$');

void main() {
  test('every sticker id is unique and accepted by the server', () {
    final ids = [for (final p in stickerPacks) ...p.stickers.map((s) => s.id)];
    expect(ids, isNotEmpty);
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(serverStickerId.hasMatch(id), isTrue, reason: id);
      expect(stickerById(id), isNotNull);
    }
    expect(
      stickerPacks.first.stickers.any((s) => s.motion != StickerMotion.none),
      isTrue,
    );
    expect(stickerById('newer_pack/thing'), isNull);
  });

  testWidgets(
    'stickers render, animated or not; unknown ones show a placeholder',
    (tester) async {
      final id = stickerPacks.first.stickers.first.id;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              StickerView(stickerId: id, animate: true),
              const StickerView(stickerId: 'nope/nope'),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('STICKER\nUNAVAILABLE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  group('recent stickers', () {
    Future<ProviderContainer> make() async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          localCacheProvider.overrideWithValue(LocalCache(p)),
          currentAccountIdProvider.overrideWithValue('me'),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('newest first, no repeats, capped', () async {
      final c = await make();
      final n = c.read(recentStickersProvider.notifier);
      final all = stickerPacks.first.stickers.map((s) => s.id).toList();
      List<String?> ids() => [
        for (final i in c.read(recentStickersProvider)) i.stickerId,
      ];
      n.usedSticker(all[0]);
      n.usedSticker(all[1]);
      n.usedSticker(all[0]);
      expect(ids(), [all[0], all[1]]);
      for (final id in all) {
        n.usedSticker(id);
      }
      expect(ids().length, RecentStickersNotifier.max);
      expect(ids().first, all.last);
    });

    test("an older version's recent sticker ids carry over", () async {
      final id = stickerPacks.first.stickers.first.id;
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      await LocalCache(p).saveRecentStickers('me', [id, 'gone/gone']);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          localCacheProvider.overrideWithValue(LocalCache(p)),
          currentAccountIdProvider.overrideWithValue('me'),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(recentStickersProvider).map((i) => i.key), ['sticker:$id']);
    });

    testWidgets('the picker sends what you tap and remembers it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final picked = <String>[];
      late ProviderContainer c;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(p),
            localCacheProvider.overrideWithValue(LocalCache(p)),
            currentAccountIdProvider.overrideWithValue('me'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  c = ProviderScope.containerOf(context);
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: StickerPicker(
                      onSend: (item) {
                        picked.add(item.stickerId!);
                        ref.read(recentStickersProvider.notifier).used(item);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      // Nothing used yet: it opens on the pack.
      expect(find.text('DOODLE GANG'), findsOneWidget);
      await tester.tap(find.byType(StickerView).at(1)); // first grid item
      await tester.pump();
      expect(picked, [stickerPacks.first.stickers.first.id]);
      expect([
        for (final i in c.read(recentStickersProvider)) i.stickerId,
      ], picked);

      await tester.tap(find.bySemanticsLabel('Recent stickers'));
      await tester.pump();
      expect(find.text('RECENT'), findsOneWidget);
    });
  });

  group('keyboard GIFs and stickers', () {
    final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2]);
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
    final webp = Uint8List.fromList([
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);

    test('files keep their real format', () {
      expect(imageExtension(gif), 'gif');
      expect(imageExtension(png), 'png');
      expect(imageExtension(webp), 'webp');
      expect(imageExtension(Uint8List.fromList([0xFF, 0xD8, 0xFF])), 'jpg');
    });

    test(
      'GIFs and stickers are sent untouched so they keep animating',
      () async {
        expect(
          await prepareInsertedImage(
            gif,
            'image/gif',
            quality: ImageQuality.standard,
          ),
          same(gif),
        );
        expect(
          await prepareInsertedImage(
            png,
            'image/png',
            quality: ImageQuality.standard,
          ),
          same(png),
        );
      },
    );

    test('a GIF too big to relay is refused rather than mangled', () async {
      final huge = Uint8List(maxRawInsertBytes + 1)..setAll(0, gif);
      expect(
        await prepareInsertedImage(
          huge,
          'image/gif',
          quality: ImageQuality.standard,
        ),
        isNull,
      );
    });
  });

  test('chat list previews never show a sticker id', () {
    final m = LocalMessage()
      ..type = MessageType.sticker
      ..textContent = 'doodles/frog';
    expect(previewTextOf(m), '🙂 Sticker');
  });
}
