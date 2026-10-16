import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

void main() {
  tearDown(() => AppColors.apply(Brightness.dark));

  for (final brightness in Brightness.values) {
    testWidgets(
      'paints without errors in ${brightness.name} mode, even at odd sizes',
      (tester) async {
        AppColors.apply(brightness);
        for (final size in const [
          Size(390, 750),
          Size(1024, 400),
          Size(50, 50),
          Size.zero,
        ]) {
          tester.view.physicalSize = size == Size.zero
              ? const Size(1, 1)
              : size;
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

  test('repaints only when the palette changes', () {
    const dark = ChatBackgroundPainter(AppPalette.dark);
    expect(
      dark.shouldRepaint(const ChatBackgroundPainter(AppPalette.dark)),
      isFalse,
    );
    expect(
      dark.shouldRepaint(const ChatBackgroundPainter(AppPalette.light)),
      isTrue,
    );
  });

  testWidgets('is cached as its own layer so scrolling never repaints it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ChatBackground(),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(ChatBackground),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });
}
