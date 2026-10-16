import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_mark.dart';

void main() {
  test(
    'the in-app logo uses exactly the geometry the app icon was made from',
    () {
      final raw =
          jsonDecode(File('assets/icon/polygons_256.json').readAsStringSync())
              as List;
      final fromAsset = [
        for (final poly in raw)
          [
            for (final p in poly as List)
              Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          ],
      ];

      expect(SerafimMarkPainter.slabs.length, fromAsset.length);
      for (var i = 0; i < fromAsset.length; i++) {
        for (var j = 0; j < fromAsset[i].length; j++) {
          expect(
            (SerafimMarkPainter.slabs[i][j] - fromAsset[i][j]).distance,
            lessThan(0.01),
            reason:
                'slab $i point $j drifted from assets/icon/polygons_256.json',
          );
        }
      }
    },
  );

  test('the S is symmetrical: the bottom slab is the top slab turned 180°', () {
    const top = 0, spine = 1, bottom = 2;
    final s = SerafimMarkPainter.slabs;
    final centre = Offset(
      s[spine].map((p) => p.dx).reduce((a, b) => a + b) / 4,
      s[spine].map((p) => p.dy).reduce((a, b) => a + b) / 4,
    );
    for (var i = 0; i < 4; i++) {
      final turned = centre * 2 - s[top][i];
      expect((turned - s[bottom][i]).distance, lessThan(0.1));
    }
  });

  test('everything fits inside the 256 grid with room for the shadow', () {
    for (final slab in SerafimMarkPainter.slabs) {
      for (final p in slab) {
        expect(p.dx, inInclusiveRange(20, 236));
        expect(p.dy, inInclusiveRange(20, 236));
      }
    }
  });

  group('the icon source images exist and are the right shape', () {
    for (final name in [
      'app_icon_full.png',
      'icon_background.png',
      'icon_foreground.png',
      'icon_monochrome.png',
    ]) {
      test(name, () {
        final bytes = File('assets/icon/$name').readAsBytesSync();
        expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
        // PNG header: width and height are big-endian ints at bytes 16 and 20.
        final data = ByteData.sublistView(bytes);
        expect(data.getUint32(16), 1024);
        expect(data.getUint32(20), 1024);
      });
    }
  });

  testWidgets('the logo paints at any size without errors', (tester) async {
    for (final size in [12.0, 30.0, 96.0, 400.0]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SerafimMark(size: size)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SerafimMark)), Size(size, size));
    }
    // And without the tile.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SerafimMark(size: 40, tile: false),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the top bar shows the logo for the brand title only', (
    tester,
  ) async {
    Future<void> pump(String title) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppTopBar(title: title),
          body: const SizedBox(),
        ),
      ),
    );

    await pump('SERAFIM');
    expect(find.byType(SerafimMark), findsOneWidget);
    expect(find.text('SERAFIM'), findsOneWidget);

    await pump('DISCOVER');
    expect(find.byType(SerafimMark), findsNothing);
    expect(find.text('DISCOVER'), findsOneWidget);
  });
}
