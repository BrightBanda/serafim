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
import 'package:serafim/src/providers/draw_together_providers.dart';
import 'package:serafim/src/data/models/echo.dart';
import 'package:serafim/src/presentation/view/settings/privacy_settings_page.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/utils/image_editor/scribble.dart';
import 'package:serafim/src/utils/chat/chat_input_bar.dart';
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

/// The photo in the chat with Tamara is a file on the phone: point it at
/// one, and put it in the image cache like the others.
Future<void> _loadChatPhoto(WidgetTester tester) async {
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

/// One frame of an animation: no settling, just the picture now.
Future<void> _shootFrame(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('$_out/frames').createSync(recursive: true);
    File('$_out/frames/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
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

  testWidgets('draw together, drawn live', (tester) async {
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _loadPhotos(tester);
    await _phone(
      tester,
      key,
      mockOverrides(prefs, tab: MockTab.chats),
      drawPage(),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(MockApp)));
    startDrawing(c, 0);
    await _settle(tester);
    const frames = 45;
    for (var i = 0; i <= frames; i++) {
      startDrawing(c, i / frames);
      await _shootFrame(tester, key, 'draw_${i.toString().padLeft(3, '0')}');
    }
    await _shoot(tester, key, '07_draw');
    c.read(drawTogetherProvider.notifier).close();
    await tester.pump();
  });

  testWidgets('notifications, and a banner', (tester) async {
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _loadPhotos(tester);
    await _phone(
      tester,
      key,
      mockOverrides(prefs, tab: MockTab.chats),
      notificationsPage(),
    );
    await _shoot(tester, key, '08_notifications');
    final c = ProviderScope.containerOf(tester.element(find.byType(MockApp)));
    showCommentBanner(c);
    await _shoot(tester, key, '09_notifications_banner');
    c.read(inAppBannerProvider).dismiss(animated: false);
    await tester.pump();
  });

  testWidgets('the logo, on its own', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(512, 512);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(key: key, child: const SerafimMark(size: 512)),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/logo.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });

  // ------------------------------------------ Draw Together, the story ---

  Future<(GlobalKey, ProviderContainer)> open(
    WidgetTester tester,
    Widget page, {
    MockTab tab = MockTab.chats,
    List<PublicUser> extraFriends = const [],
  }) async {
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _loadPhotos(tester);
    await _loadChatPhoto(tester);
    await _phone(
      tester,
      key,
      mockOverrides(prefs, tab: tab, extraFriends: extraFriends),
      page,
    );
    return (
      key,
      ProviderScope.containerOf(tester.element(find.byType(MockApp))),
    );
  }

  /// Ends any session, so no invitation timer outlives the test.
  Future<void> closeDrawing(WidgetTester tester, ProviderContainer c) async {
    c.read(drawTogetherProvider.notifier).close();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('dt: the pencil menu in a chat', (tester) async {
    final (key, _) = await open(tester, conversationPage());
    await _settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(ChatInputBar),
        matching: find.byIcon(Icons.draw_outlined),
      ),
    );
    await _shoot(tester, key, 'dt_01_pencil');
  });

  testWidgets('dt: waiting for your friend', (tester) async {
    final (key, c) = await open(tester, drawPage());
    c.read(drawTogetherProvider.notifier)
      ..invite(tamara.id)
      ..heard({
        'type': 'draw',
        'op': 'invited',
        'session': 'S',
        'peer_id': tamara.id,
      });
    await _shoot(tester, key, 'dt_02_waiting');
    await closeDrawing(tester, c);
  });

  testWidgets('dt: the invitation arrives as a banner', (tester) async {
    final (key, c) = await open(tester, mainScreen());
    await _settle(tester);
    showDrawInviteBanner(c);
    await _shoot(tester, key, 'dt_03_banner');
    c.read(inAppBannerProvider).dismiss(animated: false);
    await tester.pump();
  });

  testWidgets('dt: the invitation, JOIN or not now', (tester) async {
    final (key, c) = await open(tester, drawPage());
    c
        .read(drawTogetherProvider.notifier)
        .expectInvite(session: 'S', peerId: tamara.id);
    await _shoot(tester, key, 'dt_04_invite');
    await closeDrawing(tester, c);
  });

  testWidgets('dt: the invitation inside the chat', (tester) async {
    final (key, c) = await open(tester, conversationPage());
    c
        .read(drawTogetherProvider.notifier)
        .expectInvite(session: 'S', peerId: tamara.id);
    await _shoot(tester, key, 'dt_05_invite_bar');
    await closeDrawing(tester, c);
  });

  testWidgets('dt: a friend drops out mid-drawing', (tester) async {
    final (key, c) = await open(tester, drawPage());
    startDrawing(c, 0.65);
    c.read(drawTogetherProvider.notifier).heard({
      'type': 'draw',
      'op': 'away',
      'session': 'S',
    });
    await _shoot(tester, key, 'dt_06_away');
    await closeDrawing(tester, c);
  });

  testWidgets('dt: the same canvas on Tamara\'s phone', (tester) async {
    final (key, c) = await open(tester, drawPage(), extraFriends: [meAsFriend]);
    startDrawingAsTamara(c, 0);
    await _settle(tester);
    const frames = 45;
    for (var i = 0; i <= frames; i++) {
      startDrawingAsTamara(c, i / frames);
      await _shootFrame(
        tester,
        key,
        'draw_tamara_${i.toString().padLeft(3, '0')}',
      );
    }
    await closeDrawing(tester, c);
  });

  testWidgets('dt: the drawing, sent to the chat', (tester) async {
    // The picture "Send to chat" makes, by the app's own renderer.
    final path = '$_out/dt_drawing.png';
    await tester.runAsync(() async {
      final png = await renderScribble(
        strokes: finishedDrawing(),
        displayedWidth: 1,
        paper: scribblePapers[2],
      );
      File(path).writeAsBytesSync(png);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
        FileImage(File(path)),
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: frame.image)),
        ),
      );
    });
    messagesInChat = () => conversationWithDrawing(path);
    final (key, _) = await open(tester, conversationPage());
    await _shoot(tester, key, 'dt_07_sent');
    messagesInChat = conversation;
  });

  // ------------------------------------------------------ Echos, the story ---

  testWidgets('echo: the card at the top of Chats', (tester) async {
    myEchoStatus = const MyEchoStatus();
    final (key, _) = await open(tester, mainScreen());
    await _shoot(tester, key, 'e_01_chats');
  });

  testWidgets('echo: writing one', (tester) async {
    myEchoStatus = const MyEchoStatus();
    final (key, _) = await open(tester, mainScreen());
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('echo-send')));
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('echo-text')),
        matching: find.byType(TextField),
      ),
      'Bored on a Friday night. Who wants to talk football?',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _shoot(tester, key, 'e_02_compose');
  });

  testWidgets('echo: sent, and how it is doing', (tester) async {
    myEchoStatus = MyEchoStatus(echo: myLiveEcho(), sentToday: 1);
    final (key, _) = await open(tester, mainScreen());
    await _shoot(tester, key, 'e_03_sent');
    myEchoStatus = const MyEchoStatus();
  });

  testWidgets('echo: one arrives as a banner', (tester) async {
    final (key, c) = await open(tester, mainScreen(), tab: MockTab.feed);
    // The same screen just before, for the banner to slide in over.
    await _shoot(tester, key, 'e_04_feed');
    showEchoBanner(c);
    await _shoot(tester, key, 'e_04_banner');
    c.read(inAppBannerProvider).dismiss(animated: false);
    await tester.pump();
  });

  testWidgets('echo: the card it opens', (tester) async {
    final (key, _) = await open(tester, echoPage());
    await _shoot(tester, key, 'e_05_card');
  });

  testWidgets('echo: the chat it starts', (tester) async {
    messagesInChat = echoConversation;
    final (key, _) = await open(tester, weziChatPage());
    await _shoot(tester, key, 'e_06_chat');
    messagesInChat = conversation;
  });

  testWidgets('echo: who can reach you, in Settings', (tester) async {
    final (key, _) = await open(tester, const PrivacySettingsPage());
    await _settle(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('echo-visibility-everyone')),
    );
    await _shoot(tester, key, 'e_07_settings');
  });

  testWidgets('reactions: on messages, and the picker', (tester) async {
    messagesInChat = conversationWithReactions;
    final (key, _) = await open(tester, conversationPage());
    await _shoot(tester, key, 'r_01_reactions');
    await tester.longPress(find.text('Perfect. I will bring cups'));
    await _shoot(tester, key, 'r_02_picker');
    messagesInChat = conversation;
  });
}
