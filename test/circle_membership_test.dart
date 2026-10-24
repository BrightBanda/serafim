import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/circle_service.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/presentation/view/circle_detail_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';

CircleMemberInfo person(String id, CircleRole role, int day) =>
    CircleMemberInfo(
      user: PublicUser(id: id, username: id, displayName: id.toUpperCase()),
      role: role,
      joinedAt: DateTime.utc(2026, 1, day),
    );

/// A Circle the test can shape, and a server that records what it is asked.
class _Server extends CircleService {
  _Server(this.people, {this.myRole, this.settings}) : super(Dio());

  final List<CircleMemberInfo> people;
  CircleRole? myRole;
  CircleNotificationSettings? settings;
  final calls = <String>[];
  String? refuseWith;

  CircleDetail get _detail => CircleDetail(
    summary: CircleSummary(
      id: 'c1',
      name: 'Hikers',
      visibility: CircleVisibility.private,
      memberCount: people.length,
      createdAt: DateTime.utc(2026),
      myRole: myRole,
      myNotifications: myRole == null
          ? null
          : settings ?? const CircleNotificationSettings(),
    ),
    members: people,
    postingEnabled: true,
  );

  @override
  Future<CircleDetail> detail(String id) async => _detail;

  @override
  Future<List<CircleSummary>> mine() async => const [];

  @override
  Future<CircleLeaveResult> leave(String id) async {
    calls.add('leave');
    final others = people.where((m) => m.user.id != 'me').toList();
    return CircleLeaveResult(
      circleId: id,
      left: true,
      circleDeleted: others.isEmpty,
    );
  }

  @override
  Future<CircleSummary> notificationSettings(
    String id, {
    bool? muted,
    bool? notifyPosts,
    bool? notifyReplies,
    bool? notifyMentions,
  }) async {
    calls.add('settings muted=$muted posts=$notifyPosts');
    if (refuseWith != null) throw ApiException(refuseWith!);
    settings = (settings ?? const CircleNotificationSettings()).copyWith(
      muted: muted,
      posts: notifyPosts,
      replies: notifyReplies,
      mentions: notifyMentions,
    );
    return _detail.summary;
  }
}

class _NoPosts extends PostService {
  _NoPosts() : super(Dio());

  @override
  Future<PostPage> list({
    String? circleId,
    String? authorId,
    String? cursor,
    int limit = 20,
  }) async => const PostPage(items: []);
}

/// Opens the Circle from a home screen (so leaving can go back to it) and
/// shows its About tab.
Future<void> _openAbout(WidgetTester t, _Server server) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        circleServiceProvider.overrideWithValue(server),
        postServiceProvider.overrideWithValue(_NoPosts()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CircleDetailPage(circleId: 'c1'),
                ),
              ),
              child: const Text('home'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('home'));
  await t.pumpAndSettle();
  await t.tap(find.text('ABOUT'));
  await t.pumpAndSettle();
}

bool? switchValue(WidgetTester t, String key) => t
    .widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(SwitchListTile),
      ),
    )
    .value;

bool enabled(WidgetTester t, String key) =>
    t
        .widget<SwitchListTile>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(SwitchListTile),
          ),
        )
        .onChanged !=
    null;

void main() {
  group('who takes over when the owner leaves', () {
    test('the longest-standing Overseer', () {
      final members = [
        person('me', CircleRole.owner, 1),
        person('ann', CircleRole.member, 2),
        person('bo', CircleRole.overseer, 5),
        person('cy', CircleRole.overseer, 3),
      ];
      expect(circleSuccessor(members, 'me')!.user.id, 'cy');
    });

    test('else the longest-standing member, else nobody', () {
      expect(
        circleSuccessor([
          person('me', CircleRole.owner, 1),
          person('ann', CircleRole.member, 4),
          person('bo', CircleRole.member, 2),
        ], 'me')!.user.id,
        'bo',
      );
      expect(
        circleSuccessor([person('me', CircleRole.owner, 1)], 'me'),
        isNull,
      );
    });
  });

  group('notification switches', () {
    testWidgets('every member has them, showing what the server says', (
      t,
    ) async {
      final server = _Server(
        [person('me', CircleRole.member, 1)],
        myRole: CircleRole.member,
        settings: const CircleNotificationSettings(replies: false),
      );
      await _openAbout(t, server);
      expect(switchValue(t, 'circle-mute'), isFalse);
      expect(switchValue(t, 'circle-notify-posts'), isTrue);
      expect(switchValue(t, 'circle-notify-replies'), isFalse);
    });

    testWidgets('muting saves and rests the other switches', (t) async {
      final server = _Server([
        person('me', CircleRole.member, 1),
      ], myRole: CircleRole.member);
      await _openAbout(t, server);
      await t.tap(find.byKey(const ValueKey('circle-mute')));
      await t.pumpAndSettle();
      expect(server.calls, ['settings muted=true posts=null']);
      expect(switchValue(t, 'circle-mute'), isTrue);
      expect(enabled(t, 'circle-notify-posts'), isFalse);
    });

    testWidgets('a refused change goes back and says why', (t) async {
      final server = _Server([
        person('me', CircleRole.member, 1),
      ], myRole: CircleRole.member)..refuseWith = 'Could not save that.';
      await _openAbout(t, server);
      await t.tap(find.byKey(const ValueKey('circle-notify-posts')));
      await t.pumpAndSettle();
      expect(switchValue(t, 'circle-notify-posts'), isTrue);
      expect(find.text('Could not save that.'), findsOneWidget);
    });

    testWidgets('someone outside the circle has neither switches nor Leave', (
      t,
    ) async {
      await _openAbout(t, _Server([person('ann', CircleRole.owner, 1)]));
      expect(find.byKey(const ValueKey('circle-mute')), findsNothing);
      expect(find.byKey(const ValueKey('circle-leave')), findsNothing);
    });
  });

  group('leaving', () {
    testWidgets('a member is told their posts stay, then leaves', (t) async {
      final server = _Server([
        person('ann', CircleRole.owner, 1),
        person('me', CircleRole.member, 2),
      ], myRole: CircleRole.member);
      await _openAbout(t, server);

      await t.tap(find.byKey(const ValueKey('circle-leave')));
      await t.pumpAndSettle();
      expect(find.textContaining('Your own posts stay'), findsOneWidget);
      expect(find.textContaining('approved again'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('circle-leave-confirm')));
      await t.pumpAndSettle();

      expect(server.calls, ['leave']);
      expect(find.byType(CircleDetailPage), findsNothing, reason: 'closed');
      expect(find.text('You left Hikers.'), findsOneWidget);
    });

    testWidgets('changing your mind leaves you in it', (t) async {
      final server = _Server([
        person('ann', CircleRole.owner, 1),
        person('me', CircleRole.member, 2),
      ], myRole: CircleRole.member);
      await _openAbout(t, server);
      await t.tap(find.byKey(const ValueKey('circle-leave')));
      await t.pumpAndSettle();
      await t.tap(find.text('Stay'));
      await t.pumpAndSettle();
      expect(server.calls, isEmpty);
      expect(find.byType(CircleDetailPage), findsOneWidget);
    });

    testWidgets('an owner is told who takes over', (t) async {
      final server = _Server([
        person('me', CircleRole.owner, 1),
        person('ann', CircleRole.member, 2),
        person('bo', CircleRole.overseer, 3),
      ], myRole: CircleRole.owner);
      await _openAbout(t, server);
      await t.tap(find.byKey(const ValueKey('circle-leave')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('BO (overseer) becomes the owner'),
        findsOneWidget,
      );
    });

    testWidgets('the last member is warned it will be deleted', (t) async {
      final server = _Server([
        person('me', CircleRole.owner, 1),
      ], myRole: CircleRole.owner);
      await _openAbout(t, server);
      await t.tap(find.byKey(const ValueKey('circle-leave')));
      await t.pumpAndSettle();
      expect(find.textContaining('will be deleted'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('circle-leave-confirm')));
      await t.pumpAndSettle();
      expect(find.text('Hikers was deleted.'), findsOneWidget);
    });
  });
}
