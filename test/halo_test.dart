import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/profile_service.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/service_providers.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/halo_sheet.dart';

PublicUser _friend({DateTime? halo}) =>
    PublicUser(id: 'f1', username: 'ann', displayName: 'Ann', haloUntil: halo);

class _FakeProfile extends ProfileViewModel {
  @override
  FutureOr<Profile?> build() => null;
}

class _FakeService extends ProfileService {
  _FakeService() : super(Dio());
  final lit = <int>[];
  final wingsOnlyCalls = <bool>[];
  int dimmed = 0;

  @override
  Future<DateTime> lightHalo(int minutes, {bool wingsOnly = false}) async {
    lit.add(minutes);
    wingsOnlyCalls.add(wingsOnly);
    return DateTime.now().toUtc().add(Duration(minutes: minutes));
  }

  @override
  Future<void> dimHalo() async => dimmed++;
}

void main() {
  group('what a friend shows', () {
    test('the time round-trips through the saved copy', () {
      final until = DateTime.utc(2030, 1, 1, 12);
      final back = PublicUser.fromJson(_friend(halo: until).toJson());
      expect(back.haloUntil, until);
      expect(PublicUser.fromJson(_friend().toJson()).haloUntil, isNull);
    });

    test('lit only while the time is in the future', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      bool lit(DateTime? u) {
        final sub = c.listen(haloLitProvider((id: 'f1', until: u)), (_, __) {});
        final v = sub.read();
        sub.close();
        return v;
      }

      final now = DateTime.now().toUtc();
      expect(lit(null), isFalse);
      expect(lit(now.subtract(const Duration(minutes: 1))), isFalse);
      expect(lit(now.add(const Duration(hours: 1))), isTrue);
    });

    test('a live event beats the list, both ways', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final inAnHour = DateTime.now().toUtc().add(const Duration(hours: 1));
      final key = haloKey(_friend(halo: inAnHour));
      final sub = c.listen(haloLitProvider(key), (_, __) {});
      addTearDown(sub.close);
      expect(sub.read(), isTrue);

      // They put it out.
      c.read(friendHaloProvider.notifier).heard({
        'user_id': 'f1',
        'halo_until': null,
      });
      expect(sub.read(), isFalse);

      // ...and lit it again.
      c.read(friendHaloProvider.notifier).heard({
        'user_id': 'f1',
        'halo_until': inAnHour.toIso8601String(),
      });
      expect(sub.read(), isTrue);
    });

    test('it goes out on its own when the time runs out', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final key = haloKey(
        _friend(
          halo: DateTime.now().toUtc().add(const Duration(milliseconds: 250)),
        ),
      );
      final seen = <bool>[];
      final sub = c.listen(
        haloLitProvider(key),
        (_, now) => seen.add(now),
        fireImmediately: true,
      );
      addTearDown(sub.close);
      expect(sub.read(), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(sub.read(), isFalse);
      expect(seen, [true, false]);
    });
  });

  testWidgets('a lit halo draws a ring around the photo', (t) async {
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: AvatarThumb(halo: true))),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Halo on: free to chat',
      ),
      findsOneWidget,
    );
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: AvatarThumb())));
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Halo on: free to chat',
      ),
      findsNothing,
    );
  });

  group('who sees it', () {
    testWidgets('all friends by default; Wings only when chosen', (t) async {
      final fake = _FakeService();
      Future<void> openSheet() async {
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              profileServiceProvider.overrideWithValue(fake),
              profileViewModelProvider.overrideWith(_FakeProfile.new),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => showHaloSheet(context, ref),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
      }

      await openSheet();
      await t.tap(find.byKey(const ValueKey('halo-60')));
      await t.pumpAndSettle();
      expect(fake.wingsOnlyCalls, [false]);

      await openSheet();
      await t.tap(find.byKey(const ValueKey('halo-audience-wings')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('halo-30')));
      await t.pumpAndSettle();
      expect(fake.wingsOnlyCalls, [false, true]);
    });

    test('the audience round-trips on your profile', () {
      final p = Profile.fromJson({
        'user_id': 'me',
        'display_name': 'Me',
        'username': 'me',
        'halo_audience': 'wings',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(p.haloAudience, 'wings');
      expect(Profile.fromJson(p.toJson()).haloAudience, 'wings');
      expect(
        Profile.fromJson({
          'user_id': 'me',
          'display_name': 'Me',
          'username': 'me',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        }).haloAudience,
        'friends',
      );
    });
  });

  group('the controls', () {
    late _FakeService service;

    Future<void> open(WidgetTester t) async {
      service = _FakeService();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            profileServiceProvider.overrideWithValue(service),
            profileViewModelProvider.overrideWith(_FakeProfile.new),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => showHaloSheet(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('pick a time to light it, then put it out', (t) async {
      await open(t);
      expect(find.byKey(const ValueKey('halo-off')), findsNothing);

      await t.tap(find.byKey(const ValueKey('halo-60')));
      await t.pumpAndSettle();
      expect(service.lit, [60]);
      expect(find.text('HALO'), findsNothing, reason: 'sheet closed');

      // Opening it again: it is lit, so there is a way to put it out.
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('halo-off')), findsOneWidget);
      expect(find.textContaining('Your halo is lit until'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('halo-off')));
      await t.pumpAndSettle();
      expect(service.dimmed, 1);
    });
  });
}
