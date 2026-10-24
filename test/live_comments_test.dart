import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// The server: a post whose comments other people can add to.
class _Server extends PostService {
  _Server() : super(Dio());

  final posted = <String>['First!'];
  var commentFetches = 0;

  @override
  Future<Post> detail(String id) async => Post.fromJson({
    'id': id,
    'author': {'id': 'me', 'username': 'me', 'display_name': 'Me'},
    'title': 'My post',
    'content': 'Hello',
    'comment_count': posted.length,
  });

  @override
  Future<List<PostComment>> comments(String postId) async {
    commentFetches++;
    return [
      for (final (i, text) in posted.indexed)
        PostComment.fromJson({
          'id': 'c$i',
          'post_id': postId,
          'author': {'id': 'bo', 'username': 'bo', 'display_name': 'Bo'},
          'content': text,
          'created_at': '2026-10-01T10:00:00Z',
        }),
    ];
  }
}

class _QuietWs extends WebSocketService {
  @override
  bool sendMessage(Map<String, dynamic> payload) => true;
}

void main() {
  late _Server server;
  late StreamController<Map<String, dynamic>> socket;

  Future<void> openPost(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    server = _Server();
    socket = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(socket.close);
    await t.pumpWidget(
      ProviderScope(
        retry: noAutoRetry,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          postServiceProvider.overrideWithValue(server),
          socialServiceProvider.overrideWithValue(FakeFollowSocial()),
          webSocketEventsProvider.overrideWith((ref) => socket.stream),
          webSocketServiceProvider.overrideWithValue(_QuietWs()),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(chatViewModelProvider); // as the main screen does
              return const PostDetailPage(postId: 'p1');
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('a comment notification shows the new comment at once', (
    t,
  ) async {
    await openPost(t);
    expect(find.text('First!'), findsOneWidget);

    // Bo comments; the server tells me over the socket.
    server.posted.add('Great post');
    socket.add({
      'type': 'notification',
      'id': 'n1',
      'kind': 'post_commented',
      'actor_id': 'bo',
      'actor_name': 'Bo',
      'post_id': 'p1',
    });
    await t.pumpAndSettle();

    expect(find.text('Great post'), findsOneWidget);
    expect(find.text('First!'), findsOneWidget, reason: 'nothing lost');
  });

  testWidgets('pulling down fetches comments made meanwhile', (t) async {
    await openPost(t);
    server.posted.add('Late comment');
    await t.fling(find.text('My post'), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(find.text('Late comment'), findsOneWidget);
  });

  test('opening the post again always fetches fresh comments', () async {
    final server = _Server();
    final c = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(server)],
    );
    addTearDown(c.dispose);

    var open = c.listen(postCommentsProvider('p1'), (_, __) {});
    await c.read(postCommentsProvider('p1').future);
    open.close(); // left the post
    await Future<void>.delayed(Duration.zero);

    server.posted.add('Written while I was away');
    open = c.listen(postCommentsProvider('p1'), (_, __) {});
    final list = await c.read(postCommentsProvider('p1').future);
    expect(server.commentFetches, 2);
    expect(list.map((x) => x.content), contains('Written while I was away'));
    open.close();
  });
}
