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
import 'package:serafim/src/providers/social_providers.dart';

CircleMemberInfo person(String id, CircleRole role, int day) =>
    CircleMemberInfo(
      user: PublicUser(id: id, username: id, displayName: id.toUpperCase()),
      role: role,
      joinedAt: DateTime.utc(2026, 1, day),
    );

/// A Circle the test can shape, and a server that records what it is asked.
class _Server extends CircleService {
  _Server(
    this.people, {
    this.myRole,
    this.settings,
    this.visibility = CircleVisibility.private,
    this.canInvite = false,
    this.invited = false,
  }) : super(Dio());

  final List<CircleMemberInfo> people;
  CircleRole? myRole;
  CircleNotificationSettings? settings;
  CircleVisibility visibility;
  bool canInvite;

  /// The person has an invitation waiting.
  bool invited;
  String description = 'Weekend walks';
  Map<String, Object?>? saved;
  final calls = <String>[];
  String? refuseWith;

  CircleDetail get _detail => CircleDetail(
    summary: CircleSummary(
      id: 'c1',
      name: 'Hikers',
      description: description,
      visibility: visibility,
      memberCount: people.length,
      createdAt: DateTime.utc(2026),
      myRole: myRole,
      myInvitePending: invited && myRole == null,
      myNotifications: myRole == null
          ? null
          : settings ?? const CircleNotificationSettings(),
    ),
    members: people,
    postingEnabled: true,
    canInvite: canInvite,
  );

  @override
  Future<CircleDetail> update(
    String id, {
    String? name,
    String? description,
    String? category,
    CircleVisibility? visibility,
    String? rules,
    bool? postingEnabled,
  }) async {
    saved = {
      'name': name,
      'description': description,
      'category': category,
      'visibility': visibility,
      'rules': rules,
      'posting': postingEnabled,
    };
    if (description != null) this.description = description;
    return _detail;
  }

  @override
  Future<List<CircleInviteResult>> invite(
    String id,
    List<String> userIds, {
    bool add = false,
  }) async {
    calls.add('invite ${userIds.join(',')} add=$add');
    return [
      for (final u in userIds)
        CircleInviteResult(userId: u, status: CircleInviteStatus.invited),
    ];
  }

  @override
  Future<CircleSummary> acceptInvite(String id) async {
    calls.add('accept');
    invited = false;
    myRole = CircleRole.member;
    people.add(person('me', CircleRole.member, 9));
    return _detail.summary;
  }

  @override
  Future<List<CircleSummary>> invitations() async => const [];

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

/// Opens the Circle from a home screen (so leaving can go back to it), then
/// its settings (members) or its About tab (everyone else).
Future<void> _openSettings(
  WidgetTester t,
  _Server server, {
  List<PublicUser> friends = const [],
}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        circleServiceProvider.overrideWithValue(server),
        postServiceProvider.overrideWithValue(_NoPosts()),
        friendsProvider.overrideWith((ref) async => friends),
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
  final gear = find.byKey(const ValueKey('circle-settings'));
  await t.tap(gear.evaluate().isEmpty ? find.text('ABOUT') : gear);
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
      await _openSettings(t, server);
      expect(switchValue(t, 'circle-mute'), isFalse);
      expect(switchValue(t, 'circle-notify-posts'), isTrue);
      expect(switchValue(t, 'circle-notify-replies'), isFalse);
    });

    testWidgets('muting saves and rests the other switches', (t) async {
      final server = _Server([
        person('me', CircleRole.member, 1),
      ], myRole: CircleRole.member);
      await _openSettings(t, server);
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
      await _openSettings(t, server);
      await t.tap(find.byKey(const ValueKey('circle-notify-posts')));
      await t.pumpAndSettle();
      expect(switchValue(t, 'circle-notify-posts'), isTrue);
      expect(find.text('Could not save that.'), findsOneWidget);
    });

    testWidgets('someone outside the circle has neither switches nor Leave', (
      t,
    ) async {
      await _openSettings(t, _Server([person('ann', CircleRole.owner, 1)]));
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
      await _openSettings(t, server);

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
      await _openSettings(t, server);
      await t.tap(find.byKey(const ValueKey('circle-leave')));
      await t.pumpAndSettle();
      await t.tap(find.text('Stay'));
      await t.pumpAndSettle();
      expect(server.calls, isEmpty);
      // Still in it: the Circle's page waits under its settings.
      expect(
        find.byType(CircleDetailPage, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('an owner is told who takes over', (t) async {
      final server = _Server([
        person('me', CircleRole.owner, 1),
        person('ann', CircleRole.member, 2),
        person('bo', CircleRole.overseer, 3),
      ], myRole: CircleRole.owner);
      await _openSettings(t, server);
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
      await _openSettings(t, server);
      await t.tap(find.byKey(const ValueKey('circle-leave')));
      await t.pumpAndSettle();
      expect(find.textContaining('will be deleted'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('circle-leave-confirm')));
      await t.pumpAndSettle();
      expect(find.text('Hikers was deleted.'), findsOneWidget);
    });
  });

  group('settings, editing and inviting', () {
    testWidgets('the owner edits the description', (t) async {
      final server = _Server([
        person('me', CircleRole.owner, 1),
      ], myRole: CircleRole.owner);
      await _openSettings(t, server);
      final field = find.descendant(
        of: find.byKey(const ValueKey('circle-edit-description')),
        matching: find.byType(TextField),
      );
      expect(t.widget<TextField>(field).controller!.text, 'Weekend walks');
      await t.enterText(field, 'Walks on Saturdays');
      await t.tap(find.byKey(const ValueKey('circle-edit-save')));
      await t.pumpAndSettle();
      // Only what changed is sent.
      expect(server.saved, {
        'name': null,
        'description': 'Walks on Saturdays',
        'category': null,
        'visibility': null,
        'rules': null,
        'posting': null,
      });
      expect(find.text('Circle saved.'), findsOneWidget);
    });

    testWidgets('a member cannot edit, and invites only when allowed', (
      t,
    ) async {
      final server = _Server([
        person('ann', CircleRole.owner, 1),
        person('me', CircleRole.member, 2),
      ], myRole: CircleRole.member);
      await _openSettings(t, server);
      expect(find.byKey(const ValueKey('circle-edit-save')), findsNothing);
      expect(find.textContaining('Only the Circle'), findsOneWidget);
      expect(find.byKey(const ValueKey('circle-invite')), findsNothing);
    });

    testWidgets('inviting friends who are not in it yet', (t) async {
      final server = _Server(
        [
          person('me', CircleRole.member, 1),
          person('ann', CircleRole.owner, 2),
        ],
        myRole: CircleRole.member,
        visibility: CircleVisibility.public,
        canInvite: true,
      );
      await _openSettings(
        t,
        server,
        friends: const [
          PublicUser(id: 'ann', username: 'ann', displayName: 'Ann'),
          PublicUser(id: 'bo', username: 'bo', displayName: 'Bo'),
        ],
      );
      await t.tap(find.byKey(const ValueKey('circle-invite')));
      await t.pumpAndSettle();
      // Ann is already in it; a member can't add people directly.
      expect(find.byKey(const ValueKey('circle-invite-ann')), findsNothing);
      expect(find.byKey(const ValueKey('circle-invite-add')), findsNothing);
      await t.tap(find.byKey(const ValueKey('circle-invite-bo')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('circle-invite-send')));
      await t.pumpAndSettle();
      expect(server.calls, ['invite bo add=false']);
      expect(find.text('Bo: invited.'), findsOneWidget);
    });

    testWidgets('an invited person joins from the Circle page', (t) async {
      final server = _Server(
        [person('ann', CircleRole.owner, 1)],
        invited: true,
        visibility: CircleVisibility.inviteOnly,
      );
      await _openSettings(t, server);
      await t.tap(find.byKey(const ValueKey('circle-invite-accept')));
      await t.pumpAndSettle();
      expect(server.calls, ['accept']);
      expect(find.text('You joined Hikers.'), findsOneWidget);
      expect(find.byKey(const ValueKey('circle-settings')), findsOneWidget);
    });
  });
}
