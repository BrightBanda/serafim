import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serafim/src/core/platform/incoming_share.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/forward_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';

const _channel = MethodChannel('serafim/share');

class _RecordingChat extends ChatViewModel {
  static final sent =
      <({String room, String to, String text, String? group})>[];

  @override
  ChatState build() => const ChatState();

  @override
  Future<void> sendMessage({
    required String roomId,
    required String recipientId,
    String content = '',
    Uint8List? imageBytes,
    String? replyToId,
    MessageType? type,
    String? groupId,
    bool forwarded = false,
  }) async {
    sent.add((room: roomId, to: recipientId, text: content, group: groupId));
  }
}

class _NoRooms extends ChatRoomsNotifier {
  @override
  List<LocalChatRoom> build() => const [];
}

class _NoPeers extends ConversationPeersNotifier {
  @override
  List<String> build() => const [];
}

class _OneGroup extends MyGroupsController {
  @override
  List<GroupSummary> build() => const [];
}

void main() {
  group('what arrives from other apps', () {
    ProviderContainer make() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('text is kept, trimmed; empty is ignored', () {
      final c = make();
      final n = c.read(incomingShareProvider.notifier);
      n.offer('  https://example.com/a  ');
      expect(c.read(incomingShareProvider), 'https://example.com/a');
      n.consume();
      expect(c.read(incomingShareProvider), isNull);
      n.offer('   ');
      n.offer(null);
      expect(c.read(incomingShareProvider), isNull);
    });

    test('a huge share is cut, not refused', () {
      final c = make();
      c.read(incomingShareProvider.notifier).offer('x' * 9000);
      expect(c.read(incomingShareProvider)!.length, maxSharedLength);
    });

    testWidgets('the app picks up what it was opened with, and later shares', (
      t,
    ) async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async =>
            call.method == 'takeShared' ? 'https://opened.with' : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );

      final c = make();
      await c.read(incomingShareProvider.notifier).attach();
      expect(c.read(incomingShareProvider), 'https://opened.with');

      c.read(incomingShareProvider.notifier).consume();
      // Another app shares while Serafim is already running.
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'serafim/share',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('shared', 'https://later.share'),
        ),
        (_) {},
      );
      expect(c.read(incomingShareProvider), 'https://later.share');
    });

    testWidgets('a platform with no share channel is fine', (t) async {
      // What iOS or desktop answers: "not implemented".
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async => throw MissingPluginException(),
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
      final c = make();
      await c.read(incomingShareProvider.notifier).attach();
      expect(c.read(incomingShareProvider), isNull);
    });
  });

  testWidgets('the picker sends the shared text to the chosen friend', (
    t,
  ) async {
    _RecordingChat.sent.clear();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final friend = PublicUser(id: 'f1', username: 'ann', displayName: 'Ann');

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localCacheProvider.overrideWithValue(LocalCache(prefs)),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'me', isActive: true, createdAt: DateTime.utc(2026)),
          ),
          currentAccountIdProvider.overrideWithValue('me'),
          friendsProvider.overrideWith((ref) => [friend]),
          myGroupsProvider.overrideWith(_OneGroup.new),
          conversationPeerIdsProvider.overrideWith(_NoPeers.new),
          chatRoomsProvider.overrideWith(_NoRooms.new),
          roomPreviewsProvider.overrideWithValue(const {}),
          chatViewModelProvider.overrideWith(_RecordingChat.new),
        ],
        child: const MaterialApp(
          home: ForwardPage.shareText('https://example.com/article'),
        ),
      ),
    );
    await t.pump();

    expect(find.text('SEND TO'), findsOneWidget);
    expect(find.text('https://example.com/article'), findsOneWidget);

    await t.tap(find.text('Ann'));
    await t.pump();
    await t.tap(find.text('SEND (1)'));
    await t.pumpAndSettle();

    expect(_RecordingChat.sent, hasLength(1));
    final s = _RecordingChat.sent.single;
    expect(s.text, 'https://example.com/article');
    expect(s.to, 'f1');
    expect(s.room, ChatViewModel.buildRoomId('me', 'f1'));
    expect(s.group, isNull);
  });
}
