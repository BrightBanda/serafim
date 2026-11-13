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
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:serafim/src/data/services/chat_features_service.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/data/services/nickname_service.dart';
import 'package:serafim/src/data/services/scheduled_message_service.dart';
import 'package:serafim/src/presentation/view/media_gallery_page.dart';
import 'package:serafim/src/presentation/view/scribble_page.dart';
import 'package:serafim/src/presentation/view/settings/sound_settings_page.dart';
import 'package:serafim/src/providers/chat_features_providers.dart';
import 'package:serafim/src/providers/media_library_providers.dart';
import 'package:serafim/src/providers/nickname_providers.dart';
import 'package:serafim/src/providers/scheduled_message_providers.dart';
import 'package:serafim/src/utils/chat/chat_image_gallery.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/utils/profile_menu_button.dart';
import 'package:serafim/src/utils/serafim_loader.dart';

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
    List extra = const [],
  }) async {
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _loadPhotos(tester);
    await _loadChatPhoto(tester);
    await _phone(
      tester,
      key,
      [...mockOverrides(prefs, tab: tab, extraFriends: extraFriends), ...extra],
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

  // ------------------------------------------------- 1.2.0, the release ---

  final fakePhotos = [
    for (final name in const [
      'p1015', 'p1036', 'p429', 'p1043', 'p292', 'p431', 'p1039', 'p1060',
      'p1062', 'p1080', 'p1015', 'p1036', 'p429', 'p1043', 'p292', 'p431',
    ])
      name,
  ];

  List releaseOverrides() => [
    mediaLibraryProvider.overrideWithValue(
      _PhotoLibrary([
        for (var i = 0; i < fakePhotos.length; i++)
          _Photo('m$i', '$_cache/photos/${fakePhotos[i]}.jpg', video: i % 5 == 2),
      ]),
    ),
    scheduledMessageServiceProvider.overrideWithValue(_Scheduled()),
    chatFeaturesServiceProvider.overrideWithValue(_Features()),
    nicknamesProvider.overrideWith(
      (ref) async => Nicknames(
        given: {tamara.id: 'Tamz'},
        received: {tamara.id: 'Captain'},
      ),
    ),
  ];

  testWidgets('release: the chat, and the paperclip menu', (tester) async {
    final (key, _) = await open(
      tester,
      conversationPage(),
      extra: releaseOverrides(),
    );
    await _shoot(tester, key, 'n_01_chat');
    await tester.tap(find.byKey(const ValueKey('attach-button')));
    await _shoot(tester, key, 'n_02_sheet');
    await tester.tap(find.byKey(const ValueKey('media-m1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('media-m3')));
    await _shoot(tester, key, 'n_03_sheet_picked');
  });

  testWidgets('release: scheduled messages', (tester) async {
    final (key, c) = await open(
      tester,
      conversationPage(),
      extra: releaseOverrides(),
    );
    await _settle(tester);
    await c.read(scheduledMessagesProvider.notifier).refresh();
    await tester.tap(find.byKey(const ValueKey('attach-button')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('attach-schedule')));
    await _shoot(tester, key, 'n_04_scheduled');
    await tester.tap(find.byKey(const ValueKey('scheduled-new')));
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('schedule-text')),
        matching: find.byType(TextField),
      ),
      'Happy birthday Tamara!',
    );
    await tester.tap(find.text('Tomorrow, 8 AM'));
    FocusManager.instance.primaryFocus?.unfocus();
    await _shoot(tester, key, 'n_05_schedule_new');
  });

  testWidgets('release: the gallery and the audio list', (tester) async {
    final (key, _) = await open(
      tester,
      const MediaGalleryPage(filter: MediaFilter.visual),
      extra: releaseOverrides(),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('media-m0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('media-m4')));
    await _shoot(tester, key, 'n_06_gallery');
  });

  testWidgets('release: the menu, and chat features', (tester) async {
    final (key, _) = await open(
      tester,
      conversationPage(),
      extra: releaseOverrides(),
    );
    await _settle(tester);
    await tester.tap(find.byTooltip('Chat options'));
    await _shoot(tester, key, 'n_07_chat_menu');
    await tester.tap(find.text('Chat features'));
    await _shoot(tester, key, 'n_08_chat_features');
  });

  testWidgets('release: sounds', (tester) async {
    final (key, _) = await open(tester, const SoundSettingsPage());
    await _shoot(tester, key, 'n_09_sounds');
  });

  testWidgets('release: the profile menu, with Echo', (tester) async {
    myEchoStatus = const MyEchoStatus();
    final (key, _) = await open(tester, mainScreen());
    await _settle(tester);
    await tester.tap(find.byType(ProfileMenuButton).first);
    await _shoot(tester, key, 'n_10_profile_menu');
    await tester.tap(find.text('Echo'));
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('echo-text')),
        matching: find.byType(TextField),
      ),
      'Bored on a Friday night. Who wants to talk football?',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _shoot(tester, key, 'n_11_echo_compose');
  });

  testWidgets('release: drawing, with stickers', (tester) async {
    final (key, c) = await open(tester, drawPage());
    startDrawing(c, 1);
    await _settle(tester);
    await _shoot(tester, key, 'n_12_draw');
    await tester.tap(find.byKey(const ValueKey('draw-stickers')));
    await _settle(tester);
    await _shoot(tester, key, 'n_13_stickers');
    final jelly = find.byKey(const ValueKey('draw-sticker-doodles/jellyfish'));
    await tester.ensureVisible(jelly);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(jelly);
    await _shoot(tester, key, 'n_14_placing');
    await tester.tap(find.byKey(const ValueKey('sticker-place')));
    await _shoot(tester, key, 'n_15_placed');
    c.read(drawTogetherProvider.notifier).close();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('release: edit a copy of a drawing', (tester) async {
    late String path;
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('copy');
      path = '${dir.path}/1.scribble.png';
      final png = await renderScribble(
        strokes: copyStrokes(),
        displayedWidth: 1,
        paper: scribblePapers[0],
        aspect: 1,
      );
      File(path).writeAsBytesSync(png);
    });
    final (key, _) = await open(
      tester,
      ChatImageGallery(
        images: [
          (path: path, onSave: () async {}, onDelete: null, onEdit: () async => false),
        ],
      ),
    );
    await _settleImage(tester, path);
    await _shoot(tester, key, 'n_16_viewer');
    final (key2, _) = await open(tester, ScribblePage(editing: path));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('scribble-pad')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _shoot(tester, key2, 'n_17_edit_copy');
  });

  testWidgets('release: the feed', (t) => shootTab(t, MockTab.feed, 'n_18_feed'));

  testWidgets('release: the mascot, frame by frame', (tester) async {
    // The app's own painter, one bounce every 22 frames (two beats of the
    // track at 30 fps), transparent, so it can go anywhere in the video.
    const side = 640;
    const perBounce = 22;
    final count = perBounce * LoaderFace.values.length;
    await tester.runAsync(() async {
      Directory('$_out/frames').createSync(recursive: true);
      for (var i = 0; i < count; i++) {
        final recorder = ui.PictureRecorder();
        SerafimLoaderPainter(
          beats: AlwaysStoppedAnimation(i / perBounce),
          ink: const Color(0xFFE6E2FF),
          accent: const Color(0xFF5B7FD6),
          fill: const Color(0xFF15161C),
        ).paint(Canvas(recorder), const Size.square(640));
        final image = await recorder.endRecording().toImage(side, side);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$_out/frames/mascot_${i.toString().padLeft(3, '0')}.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      }
    });
  });
}

/// A file image needs real time to decode, in turns with the test's clock.
Future<void> _settleImage(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final frame = await codec.getNextFrame();
    PaintingBinding.instance.imageCache.putIfAbsent(
      FileImage(File(path)),
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: frame.image)),
      ),
    );
  });
}

/// A smiling face, to edit a copy of.
List<Stroke> copyStrokes() {
  Stroke line(Color c, double w, List<Offset> p) =>
      Stroke(color: c, width: w, points: p);
  const blue = Color(0xFF1E88E5);
  return [
    line(const Color(0xFFE53935), 0.03, [
      for (var i = 0; i <= 48; i++)
        Offset(
          0.5 + 0.34 * math.cos(i / 48 * 2 * math.pi),
          0.5 + 0.34 * math.sin(i / 48 * 2 * math.pi),
        ),
    ]),
    line(blue, 0.05, const [Offset(0.38, 0.42)]),
    line(blue, 0.05, const [Offset(0.62, 0.42)]),
    line(blue, 0.03, [
      for (var i = 0; i <= 16; i++)
        Offset(
          0.5 + 0.17 * math.cos(math.pi * (0.1 + 0.8 * i / 16)),
          0.5 + 0.17 * math.sin(math.pi * (0.1 + 0.8 * i / 16)),
        ),
    ]),
  ];
}

/// Photos from the showcase's own folder, as the phone's media library.
class _Photo implements DeviceMedia {
  _Photo(this.id, this.path, {this.video = false});
  @override
  final String id;
  final String path;
  final bool video;
  @override
  bool get isVideo => video;
  @override
  bool get isAudio => false;
  @override
  Duration get duration => const Duration(seconds: 42);
  @override
  Future<String> name() async => '$id.jpg';
  @override
  Future<Uint8List?> thumbnail(int side) async =>
      File(path).readAsBytesSync();
  @override
  Future<File?> file() async => File(path);
  @override
  Future<Uint8List?> photoForSending({
    required int maxSide,
    required int quality,
  }) async => File(path).readAsBytesSync();
}

class _PhotoLibrary implements MediaLibrary {
  const _PhotoLibrary(this.items);
  final List<DeviceMedia> items;
  @override
  Future<MediaAccess> access(MediaFilter filter) async => MediaAccess.full;
  @override
  Future<MediaAccess> request(MediaFilter filter) async => MediaAccess.full;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> selectMore(MediaFilter filter) async {}
  @override
  Future<List<MediaAlbum>> albums(MediaFilter filter) async => const [
    MediaAlbum(id: 'recent', name: 'Recent'),
    MediaAlbum(id: 'camera', name: 'Camera'),
  ];
  @override
  Future<List<DeviceMedia>> page(MediaAlbum album, int page, int size) async =>
      page == 0 ? items : const [];
}

class _Scheduled extends ScheduledMessageService {
  _Scheduled() : super(Dio());
  @override
  Future<List<ScheduledMessage>> list() async => [
    ScheduledMessage(
      id: 's1',
      recipientId: tamara.id,
      content: 'Good luck with the interview today!',
      sendAt: DateTime.now().add(const Duration(hours: 3)),
    ),
    ScheduledMessage(
      id: 's2',
      recipientId: tamara.id,
      content: 'Remember the hike on Saturday',
      sendAt: DateTime.now().add(const Duration(days: 1)),
    ),
  ];
}

class _Features extends ChatFeaturesService {
  _Features() : super(Dio());
  @override
  Future<List<ChatFeaturesEntry>> all() async => const [];
  @override
  Future<ChatFeatures> get(ChatRef chat) async => const ChatFeatures();
}
