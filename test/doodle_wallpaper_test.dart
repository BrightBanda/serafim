import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/chat/doodle_bounds.g.dart';
import 'package:serafim/src/utils/chat/doodle_catalogue.dart';
import 'package:serafim/src/utils/chat/doodle_packing.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

void main() {
  final layout = DoodleLayout.standard();

  test('every doodle has measured bounds, and they are sane', () {
    for (final d in allDoodles) {
      final b = doodleBounds[d.name];
      expect(b, isNotNull, reason: '${d.name} has no bounds');
      expect(b!.radius, inInclusiveRange(4, 45), reason: d.name);
    }
    // Doodle names are unique (they key the bounds table).
    final names = allDoodles.map((d) => d.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('no two doodles ever touch, even across the seams', () {
    expect(layout.tightestGap, greaterThanOrEqualTo(5 - 0.01));
  });

  test('the same seed gives the identical layout every time', () {
    DoodleLayout fresh() => DoodleLayout.build(
      width: 520,
      height: 800,
      seed: 7,
      gap: 5,
      cache: false,
    );
    final a = fresh(), b = fresh();
    expect(a.items.length, b.items.length);
    for (var i = 0; i < a.items.length; i++) {
      expect(a.items[i].doodle.name, b.items[i].doodle.name);
      expect(a.items[i].at, b.items[i].at);
      expect(a.items[i].rotation, b.items[i].rotation);
    }
  });

  test('the wallpaper is genuinely packed', () {
    expect(layout.items.length, greaterThan(150));
    expect(layout.coverage, greaterThan(0.5));
  });

  test(
    'every big doodle makes it onto the wallpaper, and none sit side by side',
    () {
      final used = layout.items.map((p) => p.doodle.name).toSet();
      for (final d in bigDoodles) {
        expect(used, contains(d.name), reason: '${d.name} never got placed');
      }
      // Two of the same big doodle are never close neighbours.
      final bigs = layout.items.where((p) => !p.doodle.filler).toList();
      for (var i = 0; i < bigs.length; i++) {
        for (var j = i + 1; j < bigs.length; j++) {
          if (bigs[i].doodle.name != bigs[j].doodle.name) continue;
          final dx = math.min(
            (bigs[i].at.dx - bigs[j].at.dx).abs(),
            layout.width - (bigs[i].at.dx - bigs[j].at.dx).abs(),
          );
          final dy = math.min(
            (bigs[i].at.dy - bigs[j].at.dy).abs(),
            layout.height - (bigs[i].at.dy - bigs[j].at.dy).abs(),
          );
          final edgeGap =
              math.sqrt(dx * dx + dy * dy) - bigs[i].radius - bigs[j].radius;
          expect(
            edgeGap,
            greaterThanOrEqualTo(90 - 0.01),
            reason: bigs[i].doodle.name,
          );
        }
      }
    },
  );

  test('there are plenty of both faces and plain objects', () {
    const withFaces = {
      'goofy face',
      'cloud',
      'cool sun',
      'cactus',
      'cupcake',
      'burger',
      'heart face',
      'toast',
      'avocado',
      'frog',
    };
    const plain = {
      'rocket',
      'umbrella',
      'key',
      'camera',
      'sneaker',
      'daisy',
      'fish',
      'crown',
      'pencil',
      'headphones',
    };
    final names = bigDoodles.map((d) => d.name).toSet();
    expect(names.containsAll(withFaces), isTrue);
    expect(names.containsAll(plain), isTrue);
    expect(bigDoodles.length, greaterThanOrEqualTo(50));
  });

  test(
    'fills are barely-there tints so colour never competes with the chat',
    () {
      for (final p in [AppPalette.dark, AppPalette.light]) {
        final ink = DoodleInk(p);
        for (final tint in [ink.pink, ink.mint, ink.lemon]) {
          expect(tint.color.a, lessThanOrEqualTo(0.12));
        }
        expect(ink.line.color.a, lessThanOrEqualTo(0.21));
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('paints in ${brightness.name} mode at awkward sizes', (
      tester,
    ) async {
      final palette = brightness == Brightness.light
          ? AppPalette.light
          : AppPalette.dark;
      for (final size in const [
        Size(390, 750),
        Size(1024, 400),
        Size(60, 60),
        Size(1, 1),
        Size(1400, 1800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.expand(
              child: CustomPaint(painter: ChatDoodlePainter(palette)),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(tester.view.reset);
    });
  }

  test('repaints only when the palette changes', () {
    final dark = ChatDoodlePainter(AppPalette.dark);
    expect(dark.shouldRepaint(ChatDoodlePainter(AppPalette.dark)), isFalse);
    expect(dark.shouldRepaint(ChatDoodlePainter(AppPalette.light)), isTrue);
  });
}
