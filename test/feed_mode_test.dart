import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/services/post_service.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';

class _Server extends PostService {
  _Server() : super(Dio());
  final asked = <bool>[];

  @override
  Future<PostPage> feed({
    String? cursor,
    int limit = 20,
    bool ranked = true,
  }) async {
    asked.add(ranked);
    return const PostPage(items: []);
  }
}

void main() {
  test('the feed opens For you, and Latest asks for newest first', () async {
    final server = _Server();
    final c = ProviderContainer(
      overrides: [
        currentAccountIdProvider.overrideWithValue('me'),
        postServiceProvider.overrideWithValue(server),
      ],
    );
    addTearDown(c.dispose);
    c.listen(feedProvider, (_, _) {});
    await c.read(feedProvider.future);
    expect(c.read(feedModeProvider), FeedMode.forYou);

    c.read(feedModeProvider.notifier).set(FeedMode.latest);
    await c.read(feedProvider.future);
    expect(server.asked, [true, false]);
  });
}
