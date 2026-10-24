import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/discover_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/in_app_banner.dart';

PublicUser _p(int i) => PublicUser(
  id: 'u$i',
  username: 'user$i',
  displayName: 'Person $i',
);

Future<void> _page(WidgetTester t, int people) async {
  t.view.physicalSize = const Size(400, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        discoverProvider.overrideWith(
          (ref) => [for (var i = 0; i < people; i++) _p(i)],
        ),
        friendRequestsProvider.overrideWith((ref) => const FriendRequests()),
      ],
      child: const MaterialApp(home: DiscoverPage()),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  group('Discover shows ten at a time', () {
    testWidgets('25 people: ten, then ten more, then the rest', (t) async {
      await _page(t, 25);
      final list = find.byType(ListView);
      expect(find.text('Person 9'), findsOneWidget);
      expect(find.text('Person 10'), findsNothing, reason: 'only ten');
      await t.dragUntilVisible(
        find.text('Show more (15)'),
        list,
        const Offset(0, -300),
      );

      await t.tap(find.text('Show more (15)'));
      await t.pump();
      await t.dragUntilVisible(
        find.text('Show more (5)'),
        list,
        const Offset(0, -300),
      );
      expect(find.text('Person 19'), findsOneWidget);
      expect(find.text('Person 20'), findsNothing, reason: 'twenty so far');

      await t.tap(find.text('Show more (5)'));
      await t.pump();
      await t.dragUntilVisible(
        find.text('Person 24'),
        list,
        const Offset(0, -300),
      );
      expect(find.textContaining('Show more'), findsNothing);
    });

    testWidgets('ten or fewer: no button', (t) async {
      await _page(t, 10);
      expect(find.textContaining('Person '), findsNWidgets(10));
      expect(find.textContaining('Show more'), findsNothing);
    });
  });

  group('the in-app banner', () {
    Future<InAppBannerService> showBanner(WidgetTester t) async {
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      final service = InAppBannerService(key);
      service.show(title: 'Ann', body: 'hello there');
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      return service;
    }

    testWidgets('swipe right or left dismisses it', (t) async {
      for (final dx in [400.0, -400.0]) {
        await showBanner(t);
        expect(find.text('hello there'), findsOneWidget);
        await t.fling(find.text('hello there'), Offset(dx, 0), 2000);
        await t.pumpAndSettle();
        expect(find.text('hello there'), findsNothing, reason: 'dx=$dx');
      }
    });

    testWidgets('a small nudge springs back and it stays', (t) async {
      await showBanner(t);
      await t.drag(find.text('hello there'), const Offset(30, 0));
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('hello there'), findsOneWidget);
      // Let its own timer end it, so no timer is left pending.
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
    });
  });
}
