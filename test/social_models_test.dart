import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/attachment_download_service.dart';
import 'package:serafim/src/utils/app_bottom_nav.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/chat/message_actions.dart';

void main() {
  group('discoverReason', () {
    test('is null when nothing is shared (never invented)', () {
      expect(discoverReason(const []), isNull);
    });
    test('names a single shared interest', () {
      expect(discoverReason(const ['movies']), 'Also interested in movies');
    });
    test('lists up to three and counts the rest', () {
      expect(
        discoverReason(const ['a', 'b']),
        'Shares your interests: a and b',
      );
      expect(
        discoverReason(const ['a', 'b', 'c']),
        'Shares your interests: a, b and c',
      );
      expect(
        discoverReason(const ['a', 'b', 'c', 'd', 'e']),
        'Shares your interests: a, b and c +2 more',
      );
    });
  });

  test('PublicUser parses the backend payload without any email', () {
    final u = PublicUser.fromJson({
      'id': 'u1',
      'username': 'sam',
      'display_name': 'Sam',
      'profile_pic': null,
      'interests': ['x', 'y'],
      'shared_interests': ['x'],
      'friend_status': 'request_received',
    });
    expect(u.friendStatus, FriendStatus.requestReceived);
    expect(u.sharedInterests, ['x']);
    expect(u.isFriend, isFalse);
    // Follow fields default safely when an older server omits them.
    expect(u.isFollowing, isFalse);
    expect(u.followsYou, isFalse);
    expect(u.acceptsFriendRequests, isTrue);
    expect(u.followerCount, isNull);
    expect(FriendStatus.parse('friends'), FriendStatus.friends);
    expect(FriendStatus.parse(null), FriendStatus.none);
    expect(FriendStatus.parse('weird'), FriendStatus.none);
  });

  group('availableMessageActions', () {
    List<MessageAction> actions({
      bool out = true,
      bool deleted = false,
      bool text = true,
      bool image = false,
      bool gif = false,
      bool sticker = false,
      bool file = false,
      bool onDevice = false,
      bool confirmed = true,
    }) => availableMessageActions(
      isOutgoing: out,
      isDeleted: deleted,
      hasText: text,
      isImage: image,
      isGif: gif,
      isSticker: sticker,
      isFile: file,
      fileOnDevice: onDevice,
      isConfirmed: confirmed,
    );

    test('own text: copy, edit, reply, forward, delete', () {
      expect(actions(), [
        MessageAction.copy,
        MessageAction.edit,
        MessageAction.reply,
        MessageAction.forward,
        MessageAction.delete,
      ]);
    });
    test("someone else's message: copy, reply, forward and delete", () {
      expect(actions(out: false), [
        MessageAction.copy,
        MessageAction.reply,
        MessageAction.forward,
        MessageAction.delete,
      ]);
    });
    test('images can be downloaded and deleted but never edited', () {
      expect(actions(text: false, image: true), [
        MessageAction.download,
        MessageAction.reply,
        MessageAction.forward,
        MessageAction.delete,
      ]);
      expect(actions(image: true), isNot(contains(MessageAction.edit)));
      // Received images can be deleted too.
      expect(actions(out: false, text: false, image: true), [
        MessageAction.download,
        MessageAction.reply,
        MessageAction.forward,
        MessageAction.delete,
      ]);
    });
    test('an unsent message cannot be edited, replied to or forwarded', () {
      expect(actions(confirmed: false), [
        MessageAction.copy,
        MessageAction.delete,
      ]);
      expect(actions(confirmed: false), isNot(contains(MessageAction.forward)));
      expect(actions(confirmed: false), isNot(contains(MessageAction.reply)));
    });
    test('a message deleted for everyone can only be cleared locally', () {
      expect(actions(deleted: true), [MessageAction.delete]);
    });
    test('forward is only offered for a message the server has accepted', () {
      expect(actions(), contains(MessageAction.forward));
      expect(actions(confirmed: false), isNot(contains(MessageAction.forward)));
      expect(actions(deleted: true), isNot(contains(MessageAction.forward)));
    });
    test('a confirmed sticker gets a save action', () {
      expect(actions(sticker: true), contains(MessageAction.save));
      expect(actions(sticker: false), isNot(contains(MessageAction.save)));
      // An unsent sticker is not saved.
      expect(
        actions(sticker: true, confirmed: false),
        isNot(contains(MessageAction.save)),
      );
      // A deleted sticker only offers delete.
      expect(actions(sticker: true, deleted: true), [MessageAction.delete]);
    });
    test('a downloaded video or audio file can be saved and forwarded', () {
      expect(actions(file: true, onDevice: true, text: false), [
        MessageAction.download,
        MessageAction.reply,
        MessageAction.forward,
        MessageAction.save,
        MessageAction.delete,
      ]);
    });
    test('a file not downloaded yet can still be replied to and forwarded', () {
      // Forwarding copies it on the server, so it needn't be on the phone.
      expect(actions(file: true, text: false, out: false), [
        MessageAction.reply,
        MessageAction.forward,
        MessageAction.delete,
      ]);
    });
    test('files are never edited, and unsent ones are not saved', () {
      expect(
        actions(file: true, onDevice: true),
        isNot(contains(MessageAction.edit)),
      );
      expect(
        actions(file: true, onDevice: true, confirmed: false),
        isNot(contains(MessageAction.save)),
      );
    });
    test('a confirmed GIF gets a save action', () {
      expect(actions(gif: true), contains(MessageAction.save));
      expect(actions(gif: false), isNot(contains(MessageAction.save)));
      // An unsent GIF is not saved.
      expect(
        actions(gif: true, confirmed: false),
        isNot(contains(MessageAction.save)),
      );
      // A deleted GIF only offers delete.
      expect(actions(gif: true, deleted: true), [MessageAction.delete]);
    });
  });

  group('deleteOptionsFor', () {
    DeleteOptions opts({
      bool out = true,
      bool deleted = false,
      bool sent = true,
    }) => deleteOptionsFor(
      isOutgoing: out,
      isDeleted: deleted,
      isConfirmed: sent,
    );

    test('own sent message: for me or for everyone', () {
      expect(opts().forMe, isTrue);
      expect(opts().forEveryone, isTrue);
    });
    test("someone else's message: only for me", () {
      expect(opts(out: false).forEveryone, isFalse);
      expect(opts(out: false).forMe, isTrue);
    });
    test('unsent or already-deleted: no "for everyone"', () {
      expect(opts(sent: false).forEveryone, isFalse);
      expect(opts(deleted: true).forEveryone, isFalse);
    });
  });

  test('download file names are meaningful and filesystem-safe', () {
    final name = AttachmentDownloadService.fileNameFor(
      'Sam O\'Neil!',
      DateTime(2026, 3, 4, 5, 6, 7),
    );
    expect(name, 'serafim_sam_o_neil_20260304_050607.jpg');
    expect(
      AttachmentDownloadService.fileNameFor('???', DateTime(2026, 1, 1)),
      startsWith('serafim_chat_'),
    );
  });

  testWidgets(
    'chat list timestamps: today as time, then Yesterday, then date',
    (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final now = DateTime.now();
      expect(
        formatChatListTime(ctx, now),
        TimeOfDay.fromDateTime(now).format(ctx),
      );
      expect(
        formatChatListTime(ctx, now.subtract(const Duration(days: 1))),
        'Yesterday',
      );
      expect(formatChatListTime(ctx, DateTime(2020, 5, 17)), '17/05/20');
    },
  );

  testWidgets('bottom nav reports taps and highlights the selected tab', (
    tester,
  ) async {
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 1,
            onTap: (i) => tapped = i,
            items: const [
              AppBottomNavItem(
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
                label: 'Chats',
              ),
              AppBottomNavItem(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore,
                label: 'Discover',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.explore), findsOneWidget); // selected
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget); // not
    await tester.tap(find.text('CHATS'));
    expect(tapped, 0);
  });
}
