import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/data/services/report_service.dart';
import 'package:serafim/src/presentation/view/composer_page.dart';
import 'package:serafim/src/presentation/view/widgets/post_card.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/report_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const me = 'me';

Post aPost({String authorId = me, DateTime? editedAt}) => Post(
  id: 'p1',
  author: PublicUser(id: authorId, username: authorId, displayName: 'Ann'),
  title: 'Old title',
  content: 'Old words',
  createdAt: DateTime.now().toUtc(),
  editedAt: editedAt,
  sparkCount: 0,
  commentCount: 0,
  sparked: false,
  pinned: false,
);

class _Posts extends PostService {
  _Posts() : super(Dio());
  final edits = <String>[];

  @override
  Future<Post> edit(
    String id, {
    required String title,
    required String content,
  }) async {
    edits.add('$id $title | $content');
    return aPost();
  }
}

class _Reports extends ReportService {
  _Reports() : super(const _NoDio());
  final sent = <String>[];

  @override
  Future<void> report({
    required ReportTarget target,
    required String id,
    required ReportReason reason,
    String? note,
  }) async => sent.add('${target.name} $id ${reason.name} ${note ?? ''}');
}

class _NoDio implements Dio {
  const _NoDio();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester t,
  Widget home, {
  _Posts? posts,
  _Reports? reports,
}) async {
  t.view.physicalSize = const Size(900, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentAccountIdProvider.overrideWithValue(me),
        postServiceProvider.overrideWithValue(posts ?? _Posts()),
        reportServiceProvider.overrideWithValue(reports ?? _Reports()),
        socialServiceProvider.overrideWithValue(FakeFollowSocial()),
        followingProvider.overrideWith((ref) async => const <PublicUser>[]),
      ],
      child: MaterialApp(home: Scaffold(body: home)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('your own post can be edited: title and text', (t) async {
    final posts = _Posts();
    await _pump(t, ComposerPage(editing: aPost()), posts: posts);
    expect(find.text('EDIT POST'), findsOneWidget);
    expect(find.text('Old title'), findsOneWidget);
    expect(find.textContaining('Add pictures'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'New title');
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(posts.edits, ['p1 New title | Old words']);
  });

  testWidgets('the composer asks for a title', (t) async {
    await _pump(t, const ComposerPage());
    expect(find.text('Title'), findsOneWidget);
    await t.tap(find.text('POST'));
    await t.pump();
    expect(find.text('Add a title.'), findsOneWidget);
  });

  testWidgets('an edited post says so', (t) async {
    await _pump(t, PostCard(post: aPost(editedAt: DateTime.now().toUtc())));
    expect(find.textContaining('edited'), findsOneWidget);
  });

  testWidgets("someone else's post can be reported with a reason", (t) async {
    final reports = _Reports();
    await _pump(
      t,
      PostCard(post: aPost(authorId: 'ann')),
      reports: reports,
    );
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('Report'));
    await t.pumpAndSettle();
    expect(find.text('REPORT THIS POST'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('report-send')));
    await t.pump();
    expect(reports.sent, isEmpty, reason: 'a reason must be picked first');
    await t.tap(find.text('Spam'));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('report-send')));
    await t.pumpAndSettle();
    expect(reports.sent, ['post p1 spam ']);
    expect(find.textContaining('Serafim team will look'), findsOneWidget);
  });
}
