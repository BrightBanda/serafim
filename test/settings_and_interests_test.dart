import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/interest_catalog.dart';
import 'package:serafim/src/data/models/app_settings.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/chat/swipe_to_reply.dart';
import 'package:serafim/src/utils/interest_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('settings', () {
    test('defaults when nothing has been saved', () async {
      final s = (await containerWith({})).read(settingsProvider);
      expect(s.sendReadReceipts, isTrue);
      expect(s.inAppAlerts, isTrue);
      expect(s.imageQuality, ImageQuality.standard);
      expect(s.retentionDays, 0);
      expect(s.textSize, TextSize.normal);
    });

    test('changes persist and are read back by a fresh app start', () async {
      final first = await containerWith({});
      final n = first.read(settingsProvider.notifier);
      n.setSendReadReceipts(false);
      n.setAlertSound(false);
      n.setImageQuality(ImageQuality.dataSaver);
      n.setRetentionDays(90);
      n.setTextSize(TextSize.large);

      // Same underlying storage, new container = app restart.
      final prefs = await SharedPreferences.getInstance();
      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);
      final s = second.read(settingsProvider);
      expect(s.sendReadReceipts, isFalse);
      expect(s.alertSound, isFalse);
      expect(s.imageQuality, ImageQuality.dataSaver);
      expect(s.retentionDays, 90);
      expect(s.textSize, TextSize.large);
    });

    test('unknown stored values fall back to defaults', () async {
      final s = (await containerWith({
        'settings.imageQuality': 'bogus',
        'settings.textSize': 'huge',
      })).read(settingsProvider);
      expect(s.imageQuality, ImageQuality.standard);
      expect(s.textSize, TextSize.normal);
    });

    test('image quality presets get smaller as quality drops', () {
      expect(
        ImageQuality.dataSaver.maxSide,
        lessThan(ImageQuality.standard.maxSide),
      );
      expect(
        ImageQuality.standard.maxSide,
        lessThan(ImageQuality.high.maxSide),
      );
    });
  });

  group('profile privacy flag', () {
    test('is sent only when changed, and defaults to allowed', () {
      expect(const ProfileUpdateRequest().isEmpty, isTrue);
      expect(const ProfileUpdateRequest(allowFriendRequests: false).toJson(), {
        'allow_friend_requests': false,
      });
      final p = Profile.fromJson({
        'user_id': 'u',
        'display_name': 'A',
        'username': 'a',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(p.allowFriendRequests, isTrue);
    });
  });

  group('interests', () {
    test('the catalog is large, unique and every category has an icon', () {
      final all = [for (final l in interestCatalog.values) ...l];
      expect(all.length, greaterThan(60));
      expect(all.map((e) => e.toLowerCase()).toSet().length, all.length);
      for (final category in interestCatalog.keys) {
        expect(interestCategoryIcons, contains(category));
      }
    });

    test('custom interests are cleaned and matched ignoring case', () {
      expect(cleanInterest('   chess   club '), 'chess club');
      expect(cleanInterest('   '), isNull);
      expect(cleanInterest('x' * 80)!.length, maxInterestLength);
      expect(hasInterest(['Chess'], 'chess'), isTrue);
      expect(hasInterest(['Chess'], 'go'), isFalse);
    });

    testWidgets('picker toggles catalog chips and adds custom ones', (
      tester,
    ) async {
      Set<String> result = {};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InterestPicker(
                initial: const {'Chess'},
                onChanged: (v) => result = v,
              ),
            ),
          ),
        ),
      );

      // An earlier custom interest is shown and can be removed.
      expect(find.text('Chess'), findsOneWidget);

      await tester.tap(find.text('Gaming'));
      await tester.pump();
      expect(result, {'Chess', 'Gaming'});

      await tester.tap(find.text('Gaming'));
      await tester.pump();
      expect(result, {'Chess'});

      await tester.ensureVisible(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '  Falconry ');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(result, {'Chess', 'Falconry'});

      // Duplicates (any case) are refused.
      await tester.enterText(find.byType(TextField), 'falconry');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(result, {'Chess', 'Falconry'});
      expect(find.textContaining('already in your list'), findsOneWidget);
    });
  });

  group('swipe to reply', () {
    Future<int> swipe(
      WidgetTester tester,
      double dx, {
      bool enabled = true,
    }) async {
      var replies = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SwipeToReply(
                enabled: enabled,
                onReply: () => replies++,
                child: const SizedBox(
                  width: 200,
                  height: 40,
                  child: Text('hi'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text('hi'), Offset(dx, 0));
      await tester.pumpAndSettle();
      return replies;
    }

    testWidgets(
      'a long swipe right replies',
      (t) async => expect(await swipe(t, 100), 1),
    );
    testWidgets(
      'a long swipe left replies',
      (t) async => expect(await swipe(t, -100), 1),
    );
    testWidgets(
      'a short swipe does nothing',
      (t) async => expect(await swipe(t, 30), 0),
    );
    testWidgets('disabled (deleted message) ignores swipes', (t) async {
      expect(await swipe(t, 100, enabled: false), 0);
    });
  });
}
