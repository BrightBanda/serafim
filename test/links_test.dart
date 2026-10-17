import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/link_preview.dart';
import 'package:serafim/src/data/services/link_preview_service.dart';
import 'package:serafim/src/providers/link_preview_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/chat/link_preview_card.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePreviews extends LinkPreviewService {
  FakePreviews(this.answers) : super(Dio());
  final Map<String, LinkPreview?> answers;
  final calls = <String>[];
  bool offline = false;

  @override
  Future<LinkPreview?> fetch(String url) async {
    calls.add(url);
    if (offline) throw Exception('offline');
    return answers[url];
  }
}

void main() {
  group('finding links', () {
    List<String> texts(String s) => findLinks(s).map((l) => l.text).toList();

    test('http, https and www links, with surrounding text', () {
      expect(texts('see https://serafim.app/a?b=1 and www.example.com now'), [
        'https://serafim.app/a?b=1',
        'www.example.com',
      ]);
      expect(
        findLinks('www.example.com').single.uri.toString(),
        'https://www.example.com',
      );
    });

    test('sentence punctuation is not part of the link', () {
      expect(texts('Look: https://example.com/page.'), [
        'https://example.com/page',
      ]);
      expect(texts('(https://example.com)'), ['https://example.com']);
      expect(texts('https://en.wikipedia.org/wiki/Dart_(language)!'), [
        'https://en.wikipedia.org/wiki/Dart_(language)',
      ]);
    });

    test('only http and https', () {
      expect(findLinks('javascript:alert(1) ftp://x.org file:///etc'), isEmpty);
      expect(safeHttpUri('javascript:alert(1)'), isNull);
      expect(safeHttpUri('https://localhost'), isNull);
      expect(safeHttpUri('https://example.com')!.host, 'example.com');
    });

    test('no links, no work', () {
      expect(findLinks('just words'), isEmpty);
      expect(
        firstLink('a https://a.io b https://b.io').toString(),
        'https://a.io',
      );
    });
  });

  testWidgets('links are underlined spans inside the message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LinkifiedText(
            'go to https://serafim.app now',
            style: TextStyle(),
            linkColor: Colors.blue,
          ),
        ),
      ),
    );
    final rich = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
    final link = rich.children![1] as TextSpan;
    expect(link.text, 'https://serafim.app');
    expect(link.style!.decoration, TextDecoration.underline);
    expect(link.recognizer, isNotNull);
  });

  group('preview card', () {
    Future<(ProviderContainer, FakePreviews)> scope(
      WidgetTester tester,
      Map<String, LinkPreview?> answers,
      Uri uri,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fake = FakePreviews(answers);
      late ProviderContainer c;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            localCacheProvider.overrideWithValue(LocalCache(prefs)),
            linkPreviewServiceProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  c = ProviderScope.containerOf(context);
                  return LinkPreviewCard(uri: uri, outgoing: false);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (c, fake);
    }

    testWidgets('shows title, description and domain', (tester) async {
      final uri = Uri.parse('https://example.com/post');
      await scope(tester, {
        '$uri': const LinkPreview(
          url: 'https://example.com/post',
          domain: 'example.com',
          title: 'A title',
          description: 'A description',
        ),
      }, uri);
      expect(find.text('A title'), findsOneWidget);
      expect(find.text('A description'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('no metadata means no card (the link stays plain)', (
      tester,
    ) async {
      final uri = Uri.parse('https://example.com/none');
      await scope(tester, {}, uri);
      expect(find.byType(Container), findsNothing);
    });
  });

  test(
    'previews are cached, including "nothing to show"; offline is retried',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fake = FakePreviews({});
      ProviderContainer make() => ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localCacheProvider.overrideWithValue(LocalCache(prefs)),
          linkPreviewServiceProvider.overrideWithValue(fake),
        ],
      );

      var c = make();
      expect(await c.read(linkPreviewProvider('https://a.io').future), isNull);
      c.dispose();
      c = make();
      await c.read(linkPreviewProvider('https://a.io').future);
      c.dispose();
      expect(fake.calls, ['https://a.io']); // second time came from the phone

      fake.offline = true;
      c = make();
      expect(await c.read(linkPreviewProvider('https://b.io').future), isNull);
      c.dispose();
      fake.offline = false;
      c = make();
      await c.read(linkPreviewProvider('https://b.io').future);
      c.dispose();
      expect(fake.calls.where((u) => u == 'https://b.io').length, 2);
    },
  );

  test('thumbnail data URIs decode; anything else is ignored', () {
    const ok = LinkPreview(
      url: 'u',
      domain: 'd',
      image: 'data:image/png;base64,iVBORw==',
    );
    const bad = LinkPreview(
      url: 'u',
      domain: 'd',
      image: 'https://tracker.example/x.png',
    );
    expect(ok.imageBytes, isNotNull);
    expect(bad.imageBytes, isNull);
  });
}
