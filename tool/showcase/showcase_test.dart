// Showcase screenshots: the real app screens, with mock data, rendered to
// PNG. Run with tool/showcase/run.sh (it fetches the fonts and photos and
// sets the paths below). Not part of the normal test suite.
//
// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as google_fonts;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mock_world.dart';

final _cache = Platform.environment['SHOWCASE_CACHE'] ?? 'build/showcase/cache';
final _out = Platform.environment['SHOWCASE_OUT'] ?? 'build/showcase';
final _icons = Platform.environment['SHOWCASE_ICONS'];

/// A phone: 412 × 915 points, drawn at 3× (1236 × 2745 pixels).
const _size = Size(412, 915);
const _pixelRatio = 3.0;

/// Real fonts instead of the test font (whose letters are all boxes).
Future<void> _loadFonts() async {
  google_fonts.httpClient = MockClient((request) async {
    final name = request.url.pathSegments.last; // <hash>.ttf
    final file = File('$_cache/fonts/$name');
    if (!file.existsSync()) return http.Response('missing $name', 404);
    return http.Response.bytes(file.readAsBytesSync(), 200);
  });
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var any = false;
    for (final path in paths) {
      if (!File(path).existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
      any = true;
    }
    if (any) await loader.load();
  }

  final icons = _icons;
  if (icons != null) {
    await load('MaterialIcons', [icons]);
    // Flutter's default font, for the few texts with no style of their own.
    final dir = File(icons).parent.path;
    await load('Roboto', [
      for (final w in ['Regular', 'Medium', 'Bold']) '$dir/Roboto-$w.ttf',
    ]);
  }
  // Two labels name "JetBrains Mono" directly rather than through
  // google_fonts; give that name the real font, as designed.
  await load('JetBrains Mono', [
    '$_cache/fonts/fc34426314d00825ccc768a0c4b1178fe704f04bd947882ef10c2b71b7e355e7.ttf',
  ]);
  // Emoji, from the system if it has them.
  await load('Noto Color Emoji', [
    '/usr/share/fonts/google-noto-color-emoji-fonts/Noto-COLRv1.ttf',
  ]);
}

/// Puts every mock photo in Flutter's image cache under the key the app's
/// network images look up, so they show without a network.
Future<void> _loadPhotos(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final entry in mockPhotos.entries) {
      final bytes = File('$_cache/photos/${entry.value}').readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
        CachedNetworkImageProvider(entry.key),
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: frame.image)),
        ),
      );
    }
  });
}

/// Lets fonts, pictures and providers settle. Font loading starts inside the
/// test's fake clock, so it only moves on when frames are pumped: alternate
/// short real waits (for file and engine work) with pumps, until nothing is
/// pending.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (i > 10 && google_fonts.pendingFontFutures.isEmpty) break;
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  await _settle(tester);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _phone(
  WidgetTester tester,
  GlobalKey key,
  List overrides,
  Widget home,
) async {
  tester.view.physicalSize = _size * _pixelRatio;
  tester.view.devicePixelRatio = _pixelRatio;
  // Room for a status bar at the top, a gesture bar at the bottom.
  tester.view.padding = const FakeViewPadding(
    top: 28 * _pixelRatio,
    bottom: 12 * _pixelRatio,
  );
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ProviderScope(
        overrides: overrides.cast(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              MockApp(home: home),
              const Positioned(left: 0, right: 0, top: 0, child: StatusBar()),
            ],
          ),
        ),
      ),
    ),
  );
}

/// google_fonts keeps fonts on disk too; give it a folder.
void _fakePathProvider() {
  final dir = Directory.systemTemp.createTempSync('showcase');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir.path,
      );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _fakePathProvider();
    await _loadFonts();
  });

  Future<void> shootTab(WidgetTester tester, MockTab tab, String name) async {
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _loadPhotos(tester);
    await _phone(tester, key, mockOverrides(prefs, tab: tab), mainScreen());
    await _shoot(tester, key, name);
  }

  testWidgets('feed', (t) => shootTab(t, MockTab.feed, '01_feed'));
  testWidgets('chats', (t) => shootTab(t, MockTab.chats, '02_chats'));
  testWidgets('discover', (t) => shootTab(t, MockTab.discover, '04_discover'));
  testWidgets('circles', (t) => shootTab(t, MockTab.circles, '05_circles'));

  Future<void> shootPage(WidgetTester tester, Widget page, String name) async {
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _loadPhotos(tester);
    await _phone(tester, key, mockOverrides(prefs, tab: MockTab.chats), page);
    await _shoot(tester, key, name);
  }

  testWidgets('a conversation', (tester) async {
    // The photo in the chat is a file on the phone: point it at one, and
    // put it in the image cache like the others.
    chatPhotoPath = '$_cache/photos/p429.jpg';
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File(chatPhotoPath).readAsBytesSync(),
      );
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
        FileImage(File(chatPhotoPath)),
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: frame.image)),
        ),
      );
    });
    await shootPage(tester, conversationPage(), '03_chat');
  });

  testWidgets('a post', (t) => shootPage(t, postPage(), '06_post'));
}
