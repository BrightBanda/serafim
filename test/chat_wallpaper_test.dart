import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/chat_wallpaper.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/wallpaper_providers.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> make({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
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

void main() {
  test('encoding round-trips, and junk falls back to doodles', () {
    for (final w in [
      ChatWallpaper.doodles,
      ChatWallpaper.plain,
      ChatWallpaper.color('sand'),
      ChatWallpaper.gradient('aurora'),
      ChatWallpaper.image('/data/x/1.jpg'),
    ]) {
      expect(ChatWallpaper.decode(w.encode()), w);
    }
    expect(ChatWallpaper.decode(null), ChatWallpaper.doodles);
    expect(ChatWallpaper.decode('color:no-such'), ChatWallpaper.doodles);
    expect(ChatWallpaper.decode('hologram:3'), ChatWallpaper.doodles);
  });

  test(
    'per chat by default; apply-to-all replaces chat-specific choices',
    () async {
      final c = await make();
      final n = c.read(wallpaperProvider.notifier);

      await n.choose('room-a', ChatWallpaper.color('sand'), applyToAll: false);
      expect(
        c.read(roomWallpaperProvider('room-a')),
        ChatWallpaper.color('sand'),
      );
      expect(c.read(roomWallpaperProvider('room-b')), ChatWallpaper.doodles);

      await n.choose(
        'room-b',
        ChatWallpaper.gradient('ocean'),
        applyToAll: true,
      );
      expect(
        c.read(roomWallpaperProvider('room-a')),
        ChatWallpaper.gradient('ocean'),
      );
      expect(
        c.read(roomWallpaperProvider('anything')),
        ChatWallpaper.gradient('ocean'),
      );

      await n.choose('room-a', ChatWallpaper.plain, applyToAll: false);
      await n.resetRoom('room-a');
      expect(
        c.read(roomWallpaperProvider('room-a')),
        ChatWallpaper.gradient('ocean'),
      );
    },
  );

  test('choices survive a restart', () async {
    final c = await make();
    await c
        .read(wallpaperProvider.notifier)
        .choose('room-a', ChatWallpaper.color('plum'), applyToAll: false);
    final again = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        localCacheProvider.overrideWithValue(
          LocalCache(await SharedPreferences.getInstance()),
        ),
        currentAccountIdProvider.overrideWithValue('me'),
      ],
    );
    addTearDown(again.dispose);
    expect(
      again.read(roomWallpaperProvider('room-a')),
      ChatWallpaper.color('plum'),
    );
  });

  testWidgets('photos get a readability layer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatWallpaperView(wallpaper: ChatWallpaper.image('/missing.jpg')),
      ),
    );
    final scrims = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((b) => b.color == ChatWallpaperView.imageScrim);
    expect(scrims, isNotEmpty);
  });
}
