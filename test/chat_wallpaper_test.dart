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
  wallpaperOpacityTests();
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

void wallpaperOpacityTests() {
  group('wallpaper strength', () {
    test('an old saved string reads as full strength', () {
      expect(ChatWallpaper.decode('color:sand').opacity, 1.0);
      expect(ChatWallpaper.decode('image:/data/x/1.jpg').opacity, 1.0);
    });

    test('strength round trips and is left off at full', () {
      final w = ChatWallpaper.gradient('ocean', opacity: 0.6);
      expect(w.encode(), 'gradient:ocean@0.60');
      expect(ChatWallpaper.decode(w.encode()), w);
      expect(ChatWallpaper.color('sand').encode(), 'color:sand');
    });

    test('a path containing @ keeps its path', () {
      final w = ChatWallpaper.image('/data/a@b/1.jpg', opacity: 0.5);
      final back = ChatWallpaper.decode(w.encode());
      expect(back.value, '/data/a@b/1.jpg');
      expect(back.opacity, 0.5);
      expect(
        ChatWallpaper.decode('image:/data/a@b/1.jpg').value,
        '/data/a@b/1.jpg',
      );
    });

    test('doodles and plain ignore it; others clamp', () {
      expect(ChatWallpaper.doodles.copyWithOpacity(0.3), ChatWallpaper.doodles);
      expect(ChatWallpaper.color('sand', opacity: 0).opacity, 0.2);
      expect(
        ChatWallpaper.color(
          'sand',
        ).sameBackground(ChatWallpaper.color('sand', opacity: 0.5)),
        isTrue,
      );
    });
  });
}
