import 'dart:ui' show Brightness;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/app_settings.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/in_app_banner.dart';
import 'package:serafim/src/utils/rebuild_all.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

double _luminance(Color c) => c.computeLuminance();

double contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => AppColors.apply(Brightness.dark));

  group('theme choice', () {
    test('explicit choices ignore the phone; system follows it', () {
      expect(ThemeChoice.light.resolve(Brightness.dark), Brightness.light);
      expect(ThemeChoice.dark.resolve(Brightness.light), Brightness.dark);
      expect(ThemeChoice.system.resolve(Brightness.light), Brightness.light);
      expect(ThemeChoice.system.resolve(Brightness.dark), Brightness.dark);
    });

    test('unknown stored value falls back to following the system', () {
      expect(ThemeChoice.parse('bogus'), ThemeChoice.system);
      expect(ThemeChoice.parse(null), ThemeChoice.system);
      expect(ThemeChoice.parse('light'), ThemeChoice.light);
    });

    test('AppColors switches palette at runtime', () {
      AppColors.apply(Brightness.dark);
      final dark = AppColors.paper;
      AppColors.apply(Brightness.light);
      expect(AppColors.paper, isNot(dark));
      expect(AppColors.isLight, isTrue);
      AppColors.apply(Brightness.dark);
      expect(AppColors.paper, dark);
      expect(AppColors.isLight, isFalse);
    });
  });

  group('both palettes stay readable', () {
    for (final entry in {
      'dark': AppPalette.dark,
      'light': AppPalette.light,
    }.entries) {
      final p = entry.value;
      final name = entry.key;

      test('$name: body and accent text contrast with their backgrounds', () {
        for (final bg in [p.paper, p.paperAlt, p.paperRaised]) {
          expect(
            contrast(p.text, bg),
            greaterThanOrEqualTo(7),
            reason: '$name text on $bg',
          );
          expect(
            contrast(p.textDim, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name dim text on $bg',
          );
          expect(
            contrast(p.primaryPale, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name primaryPale on $bg',
          );
          expect(
            contrast(p.tealPale, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name tealPale on $bg',
          );
          expect(
            contrast(p.rustPale, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name rustPale on $bg',
          );
        }
      });

      test('$name: white text on the brand-blue buttons is legible', () {
        // The dark blue is the original design (3.85:1, and buttons fade into
        // primaryDeep); the light palette is held to the stricter 4.5.
        expect(
          contrast(Colors.white, p.primary),
          greaterThanOrEqualTo(p.brightness == Brightness.light ? 4.5 : 3.5),
        );
        expect(
          contrast(Colors.white, p.primaryDeep),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    test('light is actually light and dark is actually dark', () {
      expect(AppPalette.light.paper.computeLuminance(), greaterThan(0.6));
      expect(AppPalette.dark.paper.computeLuminance(), lessThan(0.05));
    });
  });

  testWidgets(
    'switching the palette repaints const widgets after a rebuild-all',
    (tester) async {
      AppColors.apply(Brightness.dark);
      final darkPaper = AppColors.paper;

      // A const subtree that reads AppColors while building.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _PaperBox(),
        ),
      );
      Color painted() =>
          (tester.widget<ColoredBox>(find.byType(ColoredBox))).color;
      expect(painted(), darkPaper);

      AppColors.apply(Brightness.light);
      await tester.pump();
      expect(
        painted(),
        darkPaper,
        reason: 'const subtree is cached until nudged',
      );

      rebuildEverythingBelow(tester.element(find.byType(Directionality)));
      await tester.pump();
      expect(painted(), AppPalette.light.paper);
    },
  );

  group('safe area', () {
    Future<void> pumpWithStatusBar(
      WidgetTester tester,
      Widget scaffold,
      double top,
    ) {
      return tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            padding: EdgeInsets.only(top: top, bottom: 20),
          ),
          child: MaterialApp(home: scaffold),
        ),
      );
    }

    testWidgets('the top bar content sits below the status bar', (
      tester,
    ) async {
      await pumpWithStatusBar(
        tester,
        const Scaffold(
          appBar: AppTopBar(title: 'TITLE'),
          body: SizedBox(),
        ),
        44,
      );
      expect(
        tester.getTopLeft(find.text('TITLE')).dy,
        greaterThanOrEqualTo(44),
      );
      // ...while its background still fills the status-bar area.
      final bar = tester.getRect(find.byType(AppTopBar));
      expect(bar.top, 0);
      expect(bar.height, 44 + 56);
    });

    testWidgets('with no status bar inset the bar is its normal 56px', (
      tester,
    ) async {
      await pumpWithStatusBar(
        tester,
        const Scaffold(
          appBar: AppTopBar(title: 'TITLE'),
          body: SizedBox(),
        ),
        0,
      );
      expect(tester.getRect(find.byType(AppTopBar)).height, 56);
    });
  });

  group('message banner', () {
    final navKey = GlobalKey<NavigatorState>();

    Widget app() => MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Center(child: Text('home'))),
    );

    testWidgets('shows the sender, slides in from the top, and auto-hides', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      final banner = InAppBannerService(navKey);

      banner.show(title: 'Sam Ndlovu', body: 'are you coming?');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sam Ndlovu'), findsOneWidget);
      expect(find.text('are you coming?'), findsOneWidget);
      expect(find.text('NEW MESSAGE'), findsOneWidget);
      // It is at the top of the screen.
      expect(tester.getTopLeft(find.text('NEW MESSAGE')).dy, lessThan(80));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Sam Ndlovu'), findsNothing);
    });

    testWidgets('appears above whatever page is open', (tester) async {
      await tester.pumpWidget(app());
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('chat page'))),
        ),
      );
      await tester.pumpAndSettle();

      final service = InAppBannerService(navKey);
      service.show(title: 'Alex', body: 'hi');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('chat page'), findsOneWidget);
      // Tappable (not buried): a tap lands on the banner, not the page.
      var tapped = false;
      service.show(title: 'Alex', body: 'again', onTap: () => tapped = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Alex'));
      await tester.pump();
      expect(tapped, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('a new message replaces the current banner', (tester) async {
      await tester.pumpWidget(app());
      final banner = InAppBannerService(navKey);

      banner.show(title: 'First', body: 'one');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      banner.show(title: 'Second', body: 'two');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      banner.dismiss(animated: false);
      await tester.pumpAndSettle();
    });

    testWidgets('keeps clear of the status bar', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 44),
          ),
          child: MaterialApp(navigatorKey: navKey, home: const Scaffold()),
        ),
      );
      final banner = InAppBannerService(navKey)..show(title: 'Sam', body: 'x');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getTopLeft(find.text('NEW MESSAGE')).dy,
        greaterThanOrEqualTo(44),
      );
      banner.dismiss(animated: false);
      await tester.pumpAndSettle();
    });
  });
}

class _PaperBox extends StatelessWidget {
  const _PaperBox();

  @override
  Widget build(BuildContext context) => ColoredBox(color: AppColors.paper);
}
