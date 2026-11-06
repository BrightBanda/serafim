import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/local/isar_service.dart' show RoomSummary;
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';
import 'package:serafim/src/presentation/view/user_profile_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/profile_photo_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = 'me';

PublicUser person(
  String id,
  String name,
  String username, {
  FriendStatus status = FriendStatus.friends,
}) => PublicUser(
  id: id,
  username: username,
  displayName: name,
  friendStatus: status,
);

final sam = person('sam', 'Sam Ndlovu', 'sam_n');
final alex = person('al', 'Alex Moyo', 'alexm');
final nina = person('nina', 'Nina Bell', 'ninab', status: FriendStatus.none);

class _FakeChat extends ChatViewModel {
  @override
  ChatState build() => const ChatState();
  @override
  Future<void> markRoomRead(String roomId) async {}
}

/// Pumps [child] with the chat list's providers on saved data only.
Future<void> pump(
  WidgetTester tester,
  Widget child, {
  List<PublicUser>? savedFriends,
  List<PublicUser> savedPeople = const [],
  List<String> peers = const [],
  bool serverAnswers = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final cache = LocalCache(prefs);
  if (savedFriends != null) await cache.saveFriends(me, savedFriends);
  for (final p in savedPeople) {
    await cache.savePerson(me, p);
  }

  await tester.pumpWidget(
    ProviderScope(
      retry: noAutoRetry,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localCacheProvider.overrideWithValue(cache),
        currentUserProvider.overrideWithValue(
          AppUser(id: me, isActive: true, createdAt: DateTime.utc(2026)),
        ),
        currentAccountIdProvider.overrideWithValue(me),
        // The server is slow or unreachable: nothing it would say arrives.
        friendsProvider.overrideWith(
          (ref) => serverAnswers
              ? (savedFriends ?? const <PublicUser>[])
              : Completer<List<PublicUser>>().future,
        ),
        publicUserProvider.overrideWith(
          (ref, id) => Completer<PublicUser>().future,
        ),
        conversationPeerIdsProvider.overrideWith(() => _FixedPeers(peers)),
        chatRoomsProvider.overrideWith(_NoRooms.new),
        roomMessagesStreamProvider.overrideWith(
          (ref, roomId) => Stream.value(<LocalMessage>[]),
        ),
        chatViewModelProvider.overrideWith(_FakeChat.new),
      ],
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('filterPeople', () {
    final people = [
      person('1', 'Zed Sam', 'zed'),
      person('2', 'Samantha Lee', 'sammy'),
      person('3', 'Ada', 'sam_the_great'),
      person('4', 'Bo Wilson', 'bo'),
    ];

    test('matches name or username, any case', () {
      expect(filterPeople(people, 'BO').map((p) => p.id), ['4']);
      expect(filterPeople(people, 'wilson').map((p) => p.id), ['4']);
      expect(filterPeople(people, 'zed').map((p) => p.id), ['1']);
    });

    test('a leading @ is ignored', () {
      expect(filterPeople(people, '@bo').map((p) => p.id), ['4']);
    });

    test(
      'names that START with the text come first, then the rest, alphabetically',
      () {
        // "sam": Ada (@sam_the_great) and Samantha both start with it, ordered by
        // name; Zed Sam only contains it, so comes last.
        expect(filterPeople(people, 'sam').map((p) => p.id), ['3', '2', '1']);
      },
    );

    test('blank means everyone, and no match means nobody', () {
      expect(filterPeople(people, '   ').length, 4);
      expect(filterPeople(people, 'zzzz'), isEmpty);
    });
  });

  group('the chat list on a slow or missing connection', () {
    testWidgets(
      'shows your saved chats at once: no spinner while the server is slow',
      (tester) async {
        await pump(tester, const ChatListPage(), savedFriends: [sam, alex]);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Sam Ndlovu'), findsOneWidget);
        expect(find.text('Alex Moyo'), findsOneWidget);
      },
    );

    testWidgets(
      'a person you chat with but are not friends with shows from the saved copy',
      (tester) async {
        await pump(
          tester,
          const ChatListPage(),
          savedFriends: [sam],
          savedPeople: [nina],
          peers: ['sam', 'nina'],
        );
        expect(find.text('Nina Bell'), findsOneWidget);
        expect(find.text('Unknown user'), findsNothing);
      },
    );

    testWidgets('only a first launch with nothing saved shows the spinner', (
      tester,
    ) async {
      await pump(tester, const ChatListPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('searching your chats is local', () {
    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
    }

    testWidgets('results appear on every keystroke, with no waiting', (
      tester,
    ) async {
      await pump(tester, const ChatListPage(), savedFriends: [sam, alex]);
      await openSearch(tester);
      expect(find.text('Search your chats'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'al');
      await tester.pump(); // one frame — no debounce, no server
      expect(find.text('Alex Moyo'), findsOneWidget);
      expect(find.text('Sam Ndlovu'), findsNothing);
    });

    testWidgets('finds people by @username', (tester) async {
      await pump(tester, const ChatListPage(), savedFriends: [sam, alex]);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), '@sam_n');
      await tester.pump();
      expect(find.text('Sam Ndlovu'), findsOneWidget);
    });

    testWidgets(
      'includes non-friends you have chatted with, from the saved copy',
      (tester) async {
        await pump(
          tester,
          const ChatListPage(),
          savedFriends: [sam],
          savedPeople: [nina],
          peers: ['sam', 'nina'],
        );
        await openSearch(tester);
        await tester.enterText(find.byType(TextField), 'bell');
        await tester.pump();
        expect(find.text('Nina Bell'), findsOneWidget);
        expect(find.text('Sam Ndlovu'), findsNothing);
      },
    );

    testWidgets('it searches people only: there are no message results', (
      tester,
    ) async {
      await pump(tester, const ChatListPage(), savedFriends: [sam]);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'sam');
      await tester.pump();
      expect(find.text('RESULTS'), findsOneWidget);
      expect(find.text('MESSAGES'), findsNothing);
    });

    testWidgets('no match says so and offers Discover', (tester) async {
      await pump(tester, const ChatListPage(), savedFriends: [sam]);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'qwerty');
      await tester.pump();
      expect(find.text('No chats match "qwerty".'), findsOneWidget);
      expect(
        find.text('Looking for someone new? Search Discover'),
        findsOneWidget,
      );
    });

    testWidgets('closing the search brings the full list back', (tester) async {
      await pump(tester, const ChatListPage(), savedFriends: [sam, alex]);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pump();
      expect(find.text('Sam Ndlovu'), findsNothing);

      await tester.tap(find.byIcon(Icons.close).last); // the app bar's close
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Sam Ndlovu'), findsOneWidget);
      expect(find.text('Alex Moyo'), findsOneWidget);
    });

    testWidgets('the clear button empties the box but keeps searching', (
      tester,
    ) async {
      await pump(tester, const ChatListPage(), savedFriends: [sam, alex]);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close).first); // the field's own clear
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('ALL CHATS'), findsOneWidget);
      expect(find.text('Sam Ndlovu'), findsOneWidget);
    });
  });

  group('opening someone\'s profile', () {
    testWidgets(
      'shows them instantly from the saved copy, while the server is still loading',
      (tester) async {
        await pump(
          tester,
          const UserProfilePage(userId: 'sam'),
          savedFriends: [sam],
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Sam Ndlovu'), findsOneWidget);
        expect(find.text('@sam_n'), findsOneWidget);
      },
    );

    testWidgets(
      'a person never seen before shows the spinner until the server answers',
      (tester) async {
        await pump(tester, const UserProfilePage(userId: 'stranger'));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('from the profile list you can still message them', (
      tester,
    ) async {
      await pump(
        tester,
        const UserProfilePage(userId: 'sam'),
        savedFriends: [sam],
      );
      expect(find.text('Message'), findsOneWidget);
    });

    testWidgets(
      'from their own conversation the pointless Message button is gone',
      (tester) async {
        await pump(
          tester,
          const UserProfilePage(userId: 'sam', fromChat: true),
          savedFriends: [sam],
        );
        expect(find.text('Sam Ndlovu'), findsOneWidget);
        expect(find.text('Message'), findsNothing);
        expect(
          find.text('Friends'),
          findsOneWidget,
        ); // the rest of the actions remain
      },
    );
  });

  group('the paperclip in a chat', () {
    Widget thread() => const ChatThreadPage(
      contactName: 'Sam Ndlovu',
      username: 'sam_n',
      recipientId: 'sam',
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('attach-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('offers everything, in one place, to a friend', (tester) async {
      await pump(tester, thread(), savedFriends: [sam]);
      expect(find.byIcon(Icons.draw_outlined), findsNothing, reason: 'moved');
      await openSheet(tester);
      for (final label in [
        'Gallery',
        'Camera',
        'Audio',
        'Scribble',
        'Draw together',
        'Scheduled',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.textContaining('Videos and audio:'), findsOneWidget);
    });

    testWidgets('Scribble opens the pad', (tester) async {
      await pump(tester, thread(), savedFriends: [sam]);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('attach-scribble')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scribble-pad')), findsOneWidget);
    });

    testWidgets('leaving with something typed is safe, and says you stopped', (
      tester,
    ) async {
      await pump(tester, thread(), savedFriends: [sam]);
      await tester.enterText(find.byType(TextField).last, 'half a thou');
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Scheduled opens the composer, with what you typed', (
      tester,
    ) async {
      await pump(tester, thread(), savedFriends: [sam]);
      await tester.enterText(find.byType(TextField).last, 'see you at nine');
      await tester.pump();
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('attach-schedule')));
      await tester.pumpAndSettle();
      expect(find.text('SCHEDULE A MESSAGE'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('schedule-text')),
          matching: find.text('see you at nine'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('for a non-friend the sheet still opens: scheduling is text, '
        'and the rest say why they are held back', (tester) async {
      await pump(tester, thread());
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('attach-gallery')));
      await tester.pumpAndSettle();
      expect(find.textContaining('as a friend to share'), findsOneWidget);
      expect(find.text('Gallery'), findsNothing, reason: 'the sheet closed');
      await tester.pump(const Duration(seconds: 5)); // the message goes away
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('attach-schedule')));
      await tester.pumpAndSettle();
      expect(find.text('SCHEDULE A MESSAGE'), findsOneWidget);
    });
  });

  group('the conversation header', () {
    Widget thread() => const ChatThreadPage(
      contactName: 'Sam Ndlovu',
      username: 'sam_n',
      recipientId: 'sam',
    );

    testWidgets('tapping their name opens their profile', (tester) async {
      await pump(tester, thread(), savedFriends: [sam]);
      expect(find.byType(UserProfilePage), findsNothing);

      await tester.tap(find.text('sam_n'));
      await tester.pumpAndSettle();
      expect(find.byType(UserProfilePage), findsOneWidget);
      expect(find.text('Sam Ndlovu'), findsOneWidget);
    });

    testWidgets('tapping their photo opens it full screen instead', (
      tester,
    ) async {
      await pump(tester, thread(), savedFriends: [sam]);
      // The avatar sits just left of the name.
      final name = tester.getTopLeft(find.text('sam_n'));
      await tester.tapAt(Offset(name.dx - 22, name.dy + 8));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePhotoViewer), findsOneWidget);
      expect(find.byType(UserProfilePage), findsNothing);
    });

    testWidgets(
      'the profile opened from here has no Message button, and Back returns to the chat',
      (tester) async {
        await pump(tester, thread(), savedFriends: [sam]);
        await tester.tap(find.text('sam_n'));
        await tester.pumpAndSettle();
        expect(find.text('Message'), findsNothing);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byType(UserProfilePage), findsNothing);
        expect(find.byType(ChatThreadPage), findsOneWidget);
      },
    );
  });
}

class _NoRooms extends ChatRoomsNotifier {
  @override
  List<LocalChatRoom> build() => const [];
}

class _FixedPeers extends ConversationPeersNotifier {
  _FixedPeers(this._ids);

  final List<String> _ids;

  @override
  List<String> build() => _ids;
}
