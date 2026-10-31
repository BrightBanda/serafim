import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/limited_gif.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('image_grid'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<ChatImageAttachment> photos(int n) => [
    for (var i = 0; i < n; i++)
      ChatImageAttachment(
        path:
            (File('${dir.path}/p$i.png')..writeAsBytesSync(
                  img.encodePng(img.Image(width: 8, height: 8)),
                ))
                .path,
      ),
  ];

  Future<void> pumpGrid(WidgetTester tester, int n) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ChatImageGrid(images: photos(n))),
    ),
  );

  testWidgets('at most four tiles; the fourth counts the rest', (tester) async {
    await pumpGrid(tester, 6);
    expect(find.byType(Image), findsNWidgets(4));
    // The fourth tile and the two not shown: three more to see.
    expect(find.text('+3'), findsOneWidget);
  });

  testWidgets('four or fewer show them all, with no counter', (tester) async {
    await pumpGrid(tester, 3);
    expect(find.byType(Image), findsNWidgets(3));
    expect(find.byKey(const ValueKey('chat-image-grid-more')), findsNothing);
  });

  testWidgets('the grid is compact', (tester) async {
    await pumpGrid(tester, 4);
    final width = tester
        .getSize(find.byKey(const ValueKey('chat-image-grid')))
        .width;
    expect(width, lessThanOrEqualTo(230));
  });

  testWidgets('a tile opens them all, to swipe through', (tester) async {
    await pumpGrid(tester, 6);
    await tester.tap(find.text('+3'));
    await tester.pumpAndSettle();
    expect(find.text('4 of 6'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('5 of 6'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 of 6'), findsOneWidget);
  });

  testWidgets('a GIF plays a few times, then stops with a replay button', (
    tester,
  ) async {
    final anim = img.Image(width: 4, height: 4)..frameDuration = 30;
    anim.addFrame(img.Image(width: 4, height: 4)..frameDuration = 30);
    final gif = File('${dir.path}/a.gif')
      ..writeAsBytesSync(img.encodeGif(anim));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: LimitedGif(path: gif.path, loops: 2)),
        ),
      );
      // Two frames of 30 ms, twice over, with room to spare.
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
    expect(find.byIcon(Icons.replay), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.replay));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byIcon(Icons.replay), findsNothing, reason: 'playing again');
  });

  test('GIFs are told apart by name', () {
    expect(isGifPath('/a/b/123.GIF'), isTrue);
    expect(isGifPath('/a/b/123.png'), isFalse);
  });
}
