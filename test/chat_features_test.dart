import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/services/chat_features_service.dart';
import 'package:serafim/src/presentation/view/chat_features_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/chat_features_providers.dart';
import 'package:serafim/src/data/services/nickname_service.dart';
import 'package:serafim/src/providers/nickname_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = 'aaaa';
const bob = 'bbbb';
const dmRoom = 'aaaa_bbbb';

class FakeFeatures extends ChatFeaturesService {
  FakeFeatures() : super(Dio());

  List<ChatFeaturesEntry> list = const [];
  final Map<String, ChatFeatures> server = {};
  bool refuse = false;
  final sets = <String>[];

  @override
  Future<List<ChatFeaturesEntry>> all() async => list;

  @override
  Future<ChatFeatures> get(ChatRef chat) async =>
      server[chat.id] ?? const ChatFeatures();

  @override
  Future<ChatFeatures> set(ChatRef chat, {required bool hideDeleted}) async {
    sets.add('${chat.id}=$hideDeleted');
    if (refuse) {
      throw const ApiException(
        "Only the group's owner and admins can change this.",
      );
    }
    return server[chat.id] = ChatFeatures(
      hideDeleted: hideDeleted,
      updatedBy: me,
    );
  }
}

Future<(ProviderContainer, FakeFeatures, SharedPreferences)> setUpContainer({
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final fake = FakeFeatures();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(p),
      currentAccountIdProvider.overrideWith((ref) => me),
      chatFeaturesServiceProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(c.dispose);
  return (c, fake, p);
}

void main() {
  test('defaults show deleted messages', () async {
    final (c, _, _) = await setUpContainer();
    expect(c.read(chatFeaturesProvider(dmRoom)).hideDeleted, isFalse);
  });

  test(
    'a frame from the other person applies to your room id, and is kept',
    () async {
      final (c, _, p) = await setUpContainer();
      c.read(chatFeaturesControllerProvider);
      // Bob changed it: to you, the chat is "the one with bob".
      c.read(chatFeaturesControllerProvider.notifier).heard({
        'type': 'chat_settings',
        'chat': 'direct',
        'id': bob,
        'hide_deleted': true,
        'updated_by': bob,
        'can_edit': true,
      });
      expect(c.read(chatFeaturesProvider(dmRoom)).hideDeleted, isTrue);
      expect(c.read(chatFeaturesProvider(dmRoom)).updatedBy, bob);
      c.read(chatFeaturesControllerProvider.notifier).heard({
        'chat': 'group',
        'id': 'g1',
        'hide_deleted': true,
        'can_edit': false,
      });
      expect(c.read(chatFeaturesProvider('group_g1')).canEdit, isFalse);
      expect(p.getString('chat_features.v1.$me'), contains(dmRoom));
    },
  );

  test(
    'saved features apply before the server answers; the server wins',
    () async {
      final (c, fake, _) = await setUpContainer(
        prefs: {
          'chat_features.v1.$me':
              '{"$dmRoom":{"hide_deleted":true,"can_edit":true}}',
        },
      );
      expect(c.read(chatFeaturesProvider(dmRoom)).hideDeleted, isTrue);
      fake.list = const [];
      await c.read(chatFeaturesControllerProvider.notifier).refresh();
      expect(c.read(chatFeaturesProvider(dmRoom)).hideDeleted, isFalse);
    },
  );

  test('a change shows at once, and is undone when refused', () async {
    final (c, fake, _) = await setUpContainer();
    final ctl = c.read(chatFeaturesControllerProvider.notifier);
    await ctl.setHideDeleted(const ChatRef.direct(bob), true);
    expect(fake.sets, ['$bob=true']);
    expect(c.read(chatFeaturesProvider(dmRoom)).hideDeleted, isTrue);

    fake.refuse = true;
    await expectLater(
      ctl.setHideDeleted(const ChatRef.group('g1'), true),
      throwsA(isA<ApiException>()),
    );
    expect(c.read(chatFeaturesProvider('group_g1')).hideDeleted, isFalse);
  });

  Future<FakeFeatures> pumpPage(
    WidgetTester t,
    ChatRef chat, {
    ChatFeatures server = const ChatFeatures(),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final fake = FakeFeatures()..server[chat.id] = server;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          currentAccountIdProvider.overrideWith((ref) => me),
          chatFeaturesServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          home: ChatFeaturesPage(chat: chat, name: 'Bob'),
        ),
      ),
    );
    await t.pumpAndSettle();
    return fake;
  }

  Switch showDeleted(WidgetTester t) => t.widget<Switch>(
    find.descendant(
      of: find.byKey(const ValueKey('chat-feature-show-deleted')),
      matching: find.byType(Switch),
    ),
  );

  testWidgets('either person turns "show deleted messages" off', (t) async {
    final fake = await pumpPage(t, const ChatRef.direct(bob));
    expect(find.textContaining('Either of you'), findsOneWidget);
    expect(showDeleted(t).value, isTrue);
    await t.tap(find.byKey(const ValueKey('chat-feature-show-deleted')));
    await t.pumpAndSettle();
    expect(fake.sets, ['$bob=true']);
    expect(showDeleted(t).value, isFalse);
    expect(find.text('Last changed by you.'), findsOneWidget);
  });

  testWidgets('nicknames live in chat features, for a friend only', (t) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    Future<void> pump(String? friend) => t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          currentAccountIdProvider.overrideWith((ref) => me),
          chatFeaturesServiceProvider.overrideWithValue(FakeFeatures()),
          nicknamesProvider.overrideWith(
            (ref) async => const Nicknames(
              given: {bob: 'Bobby'},
              received: {bob: 'Captain'},
            ),
          ),
        ],
        child: MaterialApp(
          home: ChatFeaturesPage(
            chat: const ChatRef.direct(bob),
            name: 'Bob',
            nicknameFriendId: friend,
          ),
        ),
      ),
    );
    await pump(bob);
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-features-nicknames')),
      findsOneWidget,
    );
    expect(find.textContaining('You call them "Bobby"'), findsOneWidget);
    expect(find.textContaining('they call you "Captain"'), findsOneWidget);
    await pump(null);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-features-nicknames')), findsNothing);
  });

  testWidgets('a plain group member can see it but not change it', (t) async {
    final fake = await pumpPage(
      t,
      const ChatRef.group('g1'),
      server: const ChatFeatures(hideDeleted: true, canEdit: false),
    );
    expect(find.textContaining('Only the owner and admins'), findsOneWidget);
    expect(showDeleted(t).value, isFalse);
    expect(showDeleted(t).onChanged, isNull);
    await t.tap(find.byKey(const ValueKey('chat-feature-show-deleted')));
    await t.pumpAndSettle();
    expect(fake.sets, isEmpty);
  });

  testWidgets('read receipts stand out on your own bubble', (t) async {
    Future<Icon> receipt(ChatMessageStatus status) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              who: 'You',
              message: 'hi',
              side: ChatBubbleSide.outgoing,
              status: status,
            ),
          ),
        ),
      );
      return t.widget<Icon>(find.byKey(ValueKey('receipt-${status.name}')));
    }

    final read = await receipt(ChatMessageStatus.read);
    final delivered = await receipt(ChatMessageStatus.delivered);
    expect(read.color, receiptRead);
    expect(delivered.color, receiptPending);
    expect(read.size, greaterThanOrEqualTo(13));
  });
}
