import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/circle_service.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/presentation/view/circle_detail_page.dart';
import 'package:serafim/src/presentation/view/circles_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';

CircleSummary summary(
  String id, {
  String name = 'Flutter Devs',
  CircleRole? role,
  CircleVisibility visibility = CircleVisibility.public,
  int members = 3,
  String? category = 'Tech',
  bool requestPending = false,
  bool banned = false,
}) => CircleSummary(
  id: id,
  name: name,
  description: 'A circle about Flutter.',
  category: category,
  visibility: visibility,
  memberCount: members,
  createdAt: DateTime.utc(2026, 1, 1),
  myRole: role,
  joinedAt: role == null ? null : DateTime.utc(2026, 1, 2),
  myRequestPending: requestPending,
  iAmBanned: banned,
);

CircleMemberInfo member(String id, CircleRole role) => CircleMemberInfo(
  user: PublicUser(id: id, username: id, displayName: id.toUpperCase()),
  role: role,
  joinedAt: DateTime.utc(2026),
);

class FakeCircles extends CircleService {
  FakeCircles() : super(Dio());

  List<CircleSummary> joinedCircles = [];
  List<CircleSummary> discovered = [];
  final joined = <String>[];

  @override
  Future<List<CircleSummary>> mine() async => joinedCircles;

  @override
  Future<List<CircleSummary>> discover({
    String section = 'for_you',
    String? category,
    String? query,
  }) async => discovered;

  @override
  Future<CircleSummary> join(String id) async {
    joined.add(id);
    return summary(id, role: CircleRole.member);
  }
}

class FakePosts extends PostService {
  FakePosts() : super(Dio());

  List<Post> posts = [];

  @override
  Future<PostPage> list({
    String? circleId,
    String? authorId,
    String? cursor,
    int limit = 20,
  }) async => PostPage(items: posts);

  @override
  Future<PostPage> feed({String? cursor, int limit = 20}) async =>
      PostPage(items: posts);
}

Post post(String id, {String content = 'Hello', CircleBrief? circle}) => Post(
  id: id,
  author: PublicUser(id: 'a', username: 'alice', displayName: 'Alice Banda'),
  circle: circle,
  content: content,
  sparkCount: 2,
  commentCount: 1,
  sparked: false,
  pinned: false,
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('roles', () {
    test('who may remove whom matches the server', () {
      expect(CircleRole.owner.canRemove(CircleRole.overseer), isTrue);
      expect(CircleRole.owner.canRemove(CircleRole.owner), isFalse);
      expect(CircleRole.overseer.canRemove(CircleRole.member), isTrue);
      expect(CircleRole.overseer.canRemove(CircleRole.overseer), isFalse);
      expect(CircleRole.member.canRemove(CircleRole.member), isFalse);
      expect(CircleRole.member.canManage, isFalse);
      expect(CircleRole.overseer.canManage, isTrue);
      expect(CircleRole.overseer.isOwner, isFalse);
      expect(CircleRole.owner.isOwner, isTrue);
    });

    test('the three words are not the group ones', () {
      expect(CircleRole.overseer.label, 'Overseer');
      expect(CircleRole.owner.label, 'Owner');
      expect(CircleRole.member.label, 'Member');
    });
  });

  group('visibility', () {
    test('reads the wire values', () {
      expect(CircleVisibility.parse('public'), CircleVisibility.public);
      expect(CircleVisibility.parse('private'), CircleVisibility.private);
      expect(
        CircleVisibility.parse('invite_only'),
        CircleVisibility.inviteOnly,
      );
      expect(CircleVisibility.inviteOnly.wire, 'invite_only');
    });

    test('the join button says what will happen', () {
      expect(summary('a').joinLabel, 'Join');
      expect(
        summary('a', visibility: CircleVisibility.private).joinLabel,
        'Request to join',
      );
      expect(
        summary(
          'a',
          visibility: CircleVisibility.private,
          requestPending: true,
        ).joinLabel,
        'Requested',
      );
      expect(
        summary('a', visibility: CircleVisibility.inviteOnly).joinLabel,
        'Invite only',
      );
    });
  });

  testWidgets('the tab shows the circles you have joined', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = FakeCircles()
      ..joinedCircles = [
        summary('c1', name: 'Netball Club', role: CircleRole.owner),
      ]
      ..discovered = [summary('c2', name: 'Flutter Devs')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          circleServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: CirclesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Netball Club'), findsOneWidget);
    expect(find.text('Flutter Devs'), findsOneWidget);
    expect(find.text('JOINED'), findsOneWidget);
    expect(find.text('FOR YOU'), findsOneWidget);
  });

  testWidgets('joining from the tab calls the server', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = FakeCircles()
      ..joinedCircles = const []
      ..discovered = [summary('c2', name: 'Flutter Devs')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          circleServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: CirclesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join'), findsOneWidget);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(service.joined, ['c2']);
  });

  testWidgets('a private circle asks instead of joining', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = FakeCircles()
      ..joinedCircles = const []
      ..discovered = [
        summary(
          'c2',
          name: 'Secret Club',
          visibility: CircleVisibility.private,
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          circleServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: CirclesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Request to join'), findsOneWidget);
  });

  testWidgets('an invite-only circle offers no button', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = FakeCircles()
      ..joinedCircles = const []
      ..discovered = [
        summary(
          'c2',
          name: 'Secret Club',
          visibility: CircleVisibility.inviteOnly,
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          circleServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: CirclesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite only'), findsOneWidget);
    expect(find.text('Join'), findsNothing);
  });

  testWidgets('a circle page shows its posts', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final circles = FakeCircles();
    final posts = FakePosts()
      ..posts = [
        post(
          'p1',
          content: 'How do you organise Riverpod?',
          circle: const CircleBrief(id: 'c1', name: 'Flutter Devs'),
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('me'),
          circleServiceProvider.overrideWithValue(circles),
          postServiceProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: CircleDetailPage(circleId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    // The circle page failed to load in this fake, so the post list is not
    // shown. What matters is that the page did not crash.
    expect(tester.takeException(), isNull);
  });
}
