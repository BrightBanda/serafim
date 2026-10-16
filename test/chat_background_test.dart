import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:serafim/src/utils/chat/doodle_packing.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

void main() {
  tearDown(() => AppColors.apply(Brightness.dark));

  for (final brightness in Brightness.values) {
    testWidgets(
      'the chat background paints in ${brightness.name} mode, even at odd sizes',
      (tester) async {
        AppColors.apply(brightness);
        for (final size in const [
          Size(390, 750),
          Size(1024, 400),
          Size(50, 50),
          Size(1, 1),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox.expand(child: ChatBackground()),
            ),
          );
          expect(tester.takeException(), isNull);
        }
        addTearDown(tester.view.reset);
      },
    );
  }

  testWidgets('it draws the doodle wallpaper, cached as its own layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ChatBackground(),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(ChatBackground),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    expect(paint.painter, isA<ChatDoodlePainter>());
    expect(
      find.descendant(
        of: find.byType(ChatBackground),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });

  test(
    'the shipped layout is instant: it is read from data, not packed at runtime',
    () {
      final sw = Stopwatch()..start();
      final layout = DoodleLayout.standard();
      expect(layout.items.length, greaterThan(150));
      expect(sw.elapsedMilliseconds, lessThan(100));
    },
  );
}
