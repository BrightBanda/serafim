import 'dart:math' as math;
// The mock people, posts, Circles and chats shown in the showcase
// screenshots, and the provider overrides that feed them to the real screens.
//
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/domain/local_chat_room.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/utils/image_editor/stroke.dart';
import 'package:serafim/src/providers/draw_together_providers.dart';
import 'package:serafim/src/presentation/view/notifications_page.dart';
import 'package:serafim/src/presentation/view/draw_together_page.dart';
import 'package:serafim/src/providers/websocket_providers.dart';
import 'package:serafim/src/data/services/websocket_service.dart';
import 'package:serafim/src/data/models/app_notification.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/circle.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/post.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';
import 'package:serafim/src/presentation/view/main_screen.dart';
import 'package:serafim/src/presentation/view/post_detail_page.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/circle_providers.dart';
import 'package:serafim/src/providers/group_providers.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/notification_providers.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/providers/post_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/providers/wings_providers.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/user_card.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = 'me';

/// Mock image address → photo file in the cache folder.
const mockPhotos = <String, String>{
  'https://img.serafim.test/tamara.jpg': 'a1027.jpg',
  'https://img.serafim.test/chisomo.jpg': 'a91.jpg',
  'https://img.serafim.test/thoko.jpg': 'a64.jpg',
  'https://img.serafim.test/kondwani.jpg': 'a177.jpg',
  'https://img.serafim.test/grace.jpg': 'a1011.jpg',
  'https://img.serafim.test/mphatso.jpg': 'a65.jpg',
  'https://img.serafim.test/limbani.jpg': 'a1005.jpg',
  'https://img.serafim.test/wezi.jpg': 'a338.jpg',
  'https://img.serafim.test/fjord.jpg': 'p1015.jpg',
  'https://img.serafim.test/snow.jpg': 'p1036.jpg',
  'https://img.serafim.test/falls.jpg': 'p1039.jpg',
  'https://img.serafim.test/valley.jpg': 'p1043.jpg',
  'https://img.serafim.test/brew.jpg': 'p1060.jpg',
  'https://img.serafim.test/pug.jpg': 'p1062.jpg',
  'https://img.serafim.test/strawberries.jpg': 'p1080.jpg',
  'https://img.serafim.test/veg.jpg': 'p292.jpg',
  'https://img.serafim.test/raspberries.jpg': 'p429.jpg',
  'https://img.serafim.test/latte.jpg': 'p431.jpg',
};

String _img(String name) => 'https://img.serafim.test/$name.jpg';

DateTime _ago({int days = 0, int hours = 0, int minutes = 0}) => DateTime.now()
    .toUtc()
    .subtract(Duration(days: days, hours: hours, minutes: minutes));

PublicUser _person(
  String id,
  String name, {
  String? pic,
  bool following = false,
  bool friend = true,
  List<String> shared = const [],
  bool halo = false,
}) => PublicUser(
  id: id,
  username: id,
  displayName: name,
  profilePic: pic == null ? null : _img(pic),
  isFollowing: following,
  friendStatus: friend ? FriendStatus.friends : FriendStatus.none,
  sharedInterests: shared,
  haloUntil: halo ? DateTime.now().add(const Duration(hours: 2)) : null,
);

final tamara = _person(
  'tamara',
  'Tamara Phiri',
  pic: 'tamara',
  following: true,
);
final chisomo = _person(
  'chisomo',
  'Chisomo Banda',
  pic: 'chisomo',
  following: true,
);
final thoko = _person('thoko', 'Thoko Nyirenda', pic: 'thoko', halo: true);
final kondwani = _person(
  'kondwani',
  'Kondwani Mwale',
  pic: 'kondwani',
  following: true,
);
final grace = _person('grace', 'Grace Chirwa', pic: 'grace');
final limbani = _person('limbani', 'Limbani Gondwe');

final friends = [tamara, chisomo, thoko, kondwani, grace, limbani];

final suggestions = [
  _person(
    'mphatso',
    'Mphatso Kachingwe',
    pic: 'mphatso',
    friend: false,
    shared: ['Photography', 'Hiking', 'Coffee'],
  ),
  _person(
    'wezi',
    'Wezi Mhango',
    pic: 'wezi',
    friend: false,
    shared: ['Music', 'Travel'],
  ),
  _person(
    'takondwa',
    'Takondwa Lungu',
    friend: false,
    shared: ['Flutter', 'Football'],
  ),
  _person('alinafe', 'Alinafe Kumwenda', friend: false, shared: ['Cooking']),
];

CircleSummary _circle(
  String id,
  String name, {
  required int members,
  String? category,
  String? icon,
  CircleRole? role,
  String? about,
  CircleVisibility visibility = CircleVisibility.public,
}) => CircleSummary(
  id: id,
  name: name,
  description: about,
  category: category,
  iconUrl: icon == null ? null : _img(icon),
  visibility: visibility,
  memberCount: members,
  createdAt: _ago(days: 90),
  myRole: role,
  joinedAt: role == null ? null : _ago(days: 30),
  myNotifications: role == null ? null : const CircleNotificationSettings(),
);

final joinedCircles = [
  _circle(
    'hikers',
    'Malawi Hikers',
    members: 1240,
    category: 'Outdoors',
    icon: 'valley',
    role: CircleRole.member,
    about: 'Trails, peaks and weekend plans across Malawi.',
  ),
  _circle(
    'photo',
    'Photography Club',
    members: 386,
    category: 'Photography',
    icon: 'falls',
    role: CircleRole.overseer,
    about: 'Share your shots, swap tips, plan photo walks.',
  ),
  _circle(
    'coffee',
    'Coffee Lovers',
    members: 512,
    category: 'Food & Drink',
    icon: 'latte',
    role: CircleRole.owner,
    about: 'Beans, brews and the best cafés in town.',
  ),
];

final forYouCircles = [
  _circle(
    'foodies',
    'Lilongwe Foodies',
    members: 2310,
    category: 'Food & Drink',
    icon: 'veg',
    about: 'Where to eat, what to cook, who to share it with.',
  ),
  _circle(
    'flutter',
    'Flutter Malawi',
    members: 418,
    category: 'Tech',
    about: 'Building apps with Flutter: questions, projects and meetups.',
  ),
  _circle(
    'pets',
    'Pet Parents',
    members: 744,
    category: 'Animals',
    icon: 'pug',
    visibility: CircleVisibility.private,
    about: 'Photos, advice and the occasional very sleepy pug.',
  ),
];

Post _post(
  String id,
  PublicUser author, {
  String? title,
  required String content,
  List<String> images = const [],
  CircleSummary? circle,
  int sparks = 0,
  int comments = 0,
  bool sparked = false,
  required DateTime at,
}) => Post(
  id: id,
  author: author,
  title: title,
  content: content,
  imageUrls: [for (final i in images) _img(i)],
  circle: circle == null ? null : CircleBrief(id: circle.id, name: circle.name),
  sparkCount: sparks,
  commentCount: comments,
  sparked: sparked,
  pinned: false,
  createdAt: at,
);

final feedPosts = [
  _post(
    'p1',
    kondwani,
    title: 'Weekend hike: worth every step',
    content:
        'Left at 5am, reached the top just as the clouds lifted. '
        'Three hours up, ten minutes of pure silence at the top. '
        'Who is coming next time?',
    images: ['fjord', 'snow', 'valley'],
    circle: joinedCircles[0],
    sparks: 48,
    comments: 12,
    sparked: true,
    at: _ago(hours: 2),
  ),
  _post(
    'p2',
    tamara,
    title: 'Saturday market haul',
    content:
        'Fresh strawberries straight from the farm stall. '
        'Smoothies at mine this afternoon, bring cups!',
    images: ['strawberries'],
    sparks: 23,
    comments: 6,
    at: _ago(hours: 5),
  ),
  _post(
    'p3',
    chisomo,
    title: 'Morning light',
    content: 'Slow coffee and the first light through the window.',
    images: ['latte'],
    circle: joinedCircles[1],
    sparks: 31,
    comments: 4,
    at: _ago(hours: 9),
  ),
];

final myProfile = Profile(
  userId: me,
  displayName: 'Daylight',
  username: 'daylight',
  profilePic: _img('limbani'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// The last message in each chat, as the chat list shows it.
Map<String, RoomPreview> chatPreviews() {
  RoomPreview p(String text, DateTime at, {String from = '', int unread = 0}) =>
      RoomPreview(
        text: text,
        timestamp: at,
        senderId: from,
        isImage: false,
        isDeleted: false,
        unread: unread,
      );
  String room(PublicUser u) => ChatViewModel.buildRoomId(me, u.id);
  return {
    room(tamara): p(
      'See you at 6! I will bring the smoothies',
      _ago(minutes: 4),
      from: 'tamara',
      unread: 2,
    ),
    room(chisomo): p(
      'Sent you the edited photos',
      _ago(minutes: 38),
      from: 'chisomo',
      unread: 1,
    ),
    room(thoko): p('Haha that pug is me on Mondays', _ago(hours: 2), from: me),
    room(kondwani): p(
      'Next hike: Zomba plateau?',
      _ago(hours: 6),
      from: 'kondwani',
    ),
    room(grace): p('Thank you so much!', _ago(days: 1), from: 'grace'),
    groupRoomId('crew'): p(
      'Who is bringing snacks?',
      _ago(minutes: 12),
      from: 'kondwani',
      unread: 5,
    ),
  };
}

final myGroups = [
  GroupSummary(
    id: 'crew',
    name: 'Hiking Crew',
    myRole: GroupRole.member,
    memberCount: 7,
    joinedAt: _ago(days: 20),
    photoUrl: _img('snow'),
  ),
];

// --------------------------------------------------- a conversation ---

final tamaraRoom = ChatViewModel.buildRoomId(me, tamara.id);

/// A chat photo is a file on the phone; the harness points this at a photo.
String chatPhotoPath = '';

LocalMessage _msg(
  String id,
  String from,
  DateTime at, {
  String? text,
  MessageType type = MessageType.text,
  String? replyTo,
  MessageStatus status = MessageStatus.read,
}) => LocalMessage()
  ..messageId = id
  ..roomId = tamaraRoom
  ..senderId = from
  ..recipientId = from == me ? tamara.id : me
  ..textContent = text
  ..type = type
  ..localMediaPath = type == MessageType.image ? chatPhotoPath : null
  ..replyToId = replyTo
  ..status = status
  ..timestamp = at;

/// Newest first, as the database hands them over.
List<LocalMessage> conversation() => [
  _msg(
    'm9',
    tamara.id,
    _ago(minutes: 4),
    text: 'See you at 6! I will bring the smoothies',
  ),
  _msg('m8', me, _ago(minutes: 6), text: 'Perfect. I will bring cups'),
  _msg(
    'm7',
    tamara.id,
    _ago(minutes: 7),
    text: 'Ooh that view! We have to go next time',
    replyTo: 'm6',
  ),
  _msg('m6', me, _ago(minutes: 9), type: MessageType.post, text: 'p1'),
  _msg('m5', me, _ago(minutes: 10), text: 'Also, look at what Kondwani posted'),
  _msg(
    'm4',
    tamara.id,
    _ago(minutes: 18),
    text: 'Got these at the market this morning',
    type: MessageType.image,
  ),
  _msg('m3', me, _ago(minutes: 20), text: 'Yes! What time works for you?'),
  _msg(
    'm2',
    tamara.id,
    _ago(minutes: 21),
    text: 'Hey! Are we still on for smoothies later?',
  ),
];

Widget conversationPage() => ChatThreadPage(
  contactName: tamara.displayName,
  recipientId: tamara.id,
  username: tamara.username,
  profilePic: tamara.profilePic,
);

// -------------------------------------------------- a post, discussed ---

final postComments = [
  PostComment(
    id: 'c1',
    postId: 'p1',
    author: tamara,
    content: 'This is stunning. Adding it to my list for next month!',
    createdAt: _ago(hours: 1, minutes: 40),
    sparkCount: 6,
    sparked: true,
  ),
  PostComment(
    id: 'c2',
    postId: 'p1',
    author: kondwani,
    parentId: 'c1',
    content: 'Come with us! We go every first Saturday.',
    createdAt: _ago(hours: 1, minutes: 20),
    sparkCount: 3,
    sparked: false,
  ),
  PostComment(
    id: 'c3',
    postId: 'p1',
    author: chisomo,
    content: 'The light in the second picture is perfect.',
    createdAt: _ago(minutes: 50),
    sparkCount: 4,
    sparked: false,
  ),
  PostComment(
    id: 'c4',
    postId: 'p1',
    author: grace,
    content: 'How long is the walk from the car park?',
    createdAt: _ago(minutes: 25),
    sparkCount: 1,
    sparked: false,
  ),
];

Widget postPage() => const PostDetailPage(postId: 'p1');

// ---------------------------------------------------------- overrides ---

enum MockTab { feed, chats, discover, circles }

class _Feed extends FeedPosts {
  @override
  Future<PostPage> fetch(String? cursor) async => PostPage(items: feedPosts);
}

class _Groups extends MyGroupsController {
  @override
  FutureOr<List<GroupSummary>> build() => myGroups;
}

class _Official extends OfficialChatController {
  @override
  Future<OfficialChatState> build() async => OfficialChatState(
    announcements: [
      Announcement(
        id: 'a1',
        content: 'Serafim 1.1.0 is here: Posts, Circles and more.',
        createdAt: _ago(hours: 1),
      ),
    ],
  );
}

class _Profile extends ProfileViewModel {
  @override
  FutureOr<Profile?> build() => myProfile;
}

class _Chat extends ChatViewModel {
  @override
  ChatState build() => const ChatState(isConnected: true);
  @override
  Future<void> markRoomRead(String roomId) async {}
}

class _NoRooms extends ChatRoomsNotifier {
  @override
  List<LocalChatRoom> build() => const [];
}

class _Peers extends ConversationPeersNotifier {
  @override
  List<String> build() => const [];
}

class _Tab extends NavigationNotifier {
  _Tab(this.index);
  final int index;
  @override
  int build() => index;
}

class _NoUpdate extends UpdateCheckController {
  @override
  Future<UpdateStatus> build() async => UpdateStatus.none;
}

class _Wings extends WingsNotifier {
  @override
  List<PublicUser> build() => [tamara];
}

class _QuietSocket extends WebSocketService {
  @override
  bool sendMessage(Map<String, dynamic> payload) => true;
}

class _Notifications extends NotificationsController {
  @override
  Future<List<AppNotification>> build() async => mockNotifications();
}

List mockOverrides(
  SharedPreferences prefs, {
  required MockTab tab,
  List<PublicUser> extraFriends = const [],
}) => [
  webSocketServiceProvider.overrideWithValue(_QuietSocket()),
  notificationsProvider.overrideWith(_Notifications.new),
  sharedPreferencesProvider.overrideWithValue(prefs),
  localCacheProvider.overrideWithValue(LocalCache(prefs)),
  currentUserProvider.overrideWithValue(
    AppUser(id: me, isActive: true, createdAt: DateTime.utc(2026)),
  ),
  currentAccountIdProvider.overrideWithValue(me),
  navigationNotifierProvider.overrideWith(() => _Tab(tab.index)),
  chatViewModelProvider.overrideWith(_Chat.new),
  pushLifecycleProvider.overrideWith((ref) {}),
  updateCheckProvider.overrideWith(_NoUpdate.new),
  profileViewModelProvider.overrideWith(_Profile.new),
  myHaloLitProvider.overrideWith((ref) => true),
  unreadNotificationCountProvider.overrideWithValue(3),
  // Feed
  feedProvider.overrideWith(_Feed.new),
  followingProvider.overrideWith((ref) => [tamara, chisomo, kondwani]),
  // Chats
  friendsProvider.overrideWith((ref) => [...friends, ...extraFriends]),
  conversationPeerIdsProvider.overrideWith(_Peers.new),
  chatRoomsProvider.overrideWith(_NoRooms.new),
  roomPreviewsProvider.overrideWithValue(chatPreviews()),
  myGroupsProvider.overrideWith(_Groups.new),
  officialChatProvider.overrideWith(_Official.new),
  wingsProvider.overrideWith(_Wings.new),
  // Discover
  discoverProvider.overrideWith((ref) => suggestions.skip(1).toList()),
  friendRequestsProvider.overrideWith(
    (ref) => FriendRequests(incoming: [suggestions[0]]),
  ),
  // Circles
  myCirclesProvider.overrideWith((ref) => joinedCircles),
  discoverCirclesProvider.overrideWith((ref, query) => forYouCircles),
  // A conversation, and the post shared in it
  roomMessagesStreamProvider.overrideWith(
    (ref, roomId) => Stream.value(messagesInChat()),
  ),
  quotedMessagesProvider.overrideWith(
    (ref, ids) async => {
      for (final m in conversation())
        if (ids.split(',').contains(m.messageId)) m.messageId: m,
    },
  ),
  postProvider.overrideWith(
    (ref, id) async => feedPosts.firstWhere((p) => p.id == id),
  ),
  postCommentsProvider.overrideWith((ref, id) async => postComments),
];

Widget mainScreen() => const MainScreen();

/// The app's own theme (dark: the original Serafim look).
class MockApp extends ConsumerWidget {
  const MockApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppColors.apply(Brightness.dark);
    final base = ThemeData.dark();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // The app's own key: the in-app banner shows in its overlay.
      navigatorKey: ref.watch(navigatorKeyProvider),
      theme: base.copyWith(
        scaffoldBackgroundColor: AppColors.paper,
        canvasColor: AppColors.paper,
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.primary,
          surface: AppColors.paper,
        ),
      ),
      home: home,
    );
  }
}

/// The time now, as a phone's status bar shows it: the mock chats are dated
/// relative to now, so the clock should agree with them.
String _clock() {
  final now = DateTime.now();
  return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
}

/// A phone's status bar, drawn over the top of each screenshot.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.fieldInput.copyWith(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(_clock(), style: style),
              const Spacer(),
              const Icon(
                Icons.signal_cellular_alt,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.wifi, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              const Icon(Icons.battery_full, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------ draw together ---

/// A stroke on the shared sheet, as the server hands the canvas over: points
/// are fractions of the square (0..1).
class _Line {
  const _Line(
    this.owner,
    this.color,
    this.width,
    this.points,
    this.from,
    this.to,
  );

  final String owner;
  final Color color;
  final double width;
  final List<Offset> points;

  /// When it is drawn, as a share of the whole animation (0..1).
  final double from;
  final double to;
}

List<Offset> _path(List<Offset> corners, {int each = 14}) => [
  for (var i = 0; i < corners.length - 1; i++)
    for (var k = 0; k < each; k++)
      Offset.lerp(corners[i], corners[i + 1], k / each)!,
  corners.last,
];

List<Offset> _arc(
  Offset c,
  double r, {
  double from = 0,
  double to = 2 * math.pi,
  int n = 48,
}) => [
  for (var i = 0; i <= n; i++)
    c +
        Offset(
              math.cos(from + (to - from) * i / n),
              math.sin(from + (to - from) * i / n),
            ) *
            r,
];

List<Offset> _heart(Offset c, double s) => [
  for (var i = 0; i <= 60; i++)
    () {
      final t = 2 * math.pi * i / 60;
      final x = 16 * math.pow(math.sin(t), 3);
      final y =
          13 * math.cos(t) -
          5 * math.cos(2 * t) -
          2 * math.cos(3 * t) -
          math.cos(4 * t);
      return c + Offset(x * s, -y * s);
    }(),
];

const _pen = 8 / 360; // a medium pen, as a share of the sheet
const _thick = 16 / 360;

/// You draw mountains with snow on top; Tamara draws a sun, its rays and a
/// heart. At the same time, like two friends on one sheet.
final _drawing = <_Line>[
  _Line(
    me,
    drawColors[5],
    _thick,
    _path(const [
      Offset(0.04, 0.80),
      Offset(0.24, 0.48),
      Offset(0.36, 0.64),
      Offset(0.55, 0.34),
      Offset(0.72, 0.62),
      Offset(0.83, 0.50),
      Offset(0.96, 0.74),
    ]),
    0.0,
    0.55,
  ),
  _Line(
    me,
    drawColors[0],
    _pen,
    _path(const [
      Offset(0.48, 0.45),
      Offset(0.52, 0.41),
      Offset(0.55, 0.45),
      Offset(0.58, 0.41),
      Offset(0.62, 0.45),
    ], each: 6),
    0.58,
    0.72,
  ),
  _Line(
    me,
    drawColors[6],
    _pen,
    _path(const [
      Offset(0.06, 0.88),
      Offset(0.30, 0.86),
      Offset(0.55, 0.90),
      Offset(0.80, 0.86),
      Offset(0.94, 0.88),
    ]),
    0.75,
    0.95,
  ),
  _Line(
    'tamara',
    drawColors[4],
    _thick,
    _arc(const Offset(0.78, 0.20), 0.085),
    0.05,
    0.42,
  ),
  for (var i = 0; i < 8; i++)
    _Line(
      'tamara',
      drawColors[3],
      _pen,
      () {
        final a = 2 * math.pi * i / 8;
        final d = Offset(math.cos(a), math.sin(a));
        return _path([
          const Offset(0.78, 0.20) + d * 0.12,
          const Offset(0.78, 0.20) + d * 0.17,
        ], each: 4);
      }(),
      0.45 + i * 0.03,
      0.48 + i * 0.03,
    ),
  _Line(
    'tamara',
    drawColors[2],
    _pen,
    _heart(const Offset(0.22, 0.20), 0.0042),
    0.75,
    1.0,
  ),
];

/// The canvas as it stands at [t] (0..1 of the animation), in the shape the
/// server sends: each person's strokes, the one being drawn cut short.
List<Map<String, dynamic>> drawingAt(double t) {
  final next = <String, int>{};
  final out = <Map<String, dynamic>>[];
  for (final line in _drawing) {
    final id = next[line.owner] = (next[line.owner] ?? -1) + 1;
    if (t <= line.from) continue;
    final share = ((t - line.from) / (line.to - line.from)).clamp(0.0, 1.0);
    final count = math.max(2, (line.points.length * share).round());
    out.add({
      'owner': line.owner,
      'id': '$id',
      'c': line.color.toARGB32(),
      'w': line.width,
      'e': false,
      'p': [
        for (final p in line.points.take(count)) ...[p.dx, p.dy],
      ],
      'done': share >= 1,
    });
  }
  return out;
}

/// Opens Draw Together with Tamara, live, on the sky paper.
void startDrawing(ProviderContainer c, double t) {
  final draw = c.read(drawTogetherProvider.notifier);
  if (c.read(drawTogetherProvider) == null) {
    draw.expectInvite(session: 'S', peerId: tamara.id);
  }
  draw.heard({
    'type': 'draw',
    'op': 'state',
    'session': 'S',
    'peer_id': tamara.id,
    'status': 'live',
    'paper': 2,
    'strokes': drawingAt(t),
  });
}

Widget drawPage() => const DrawTogetherPage();

// ------------------------------------------------------- notifications ---

List<AppNotification> mockNotifications() {
  AppNotification n(
    String id,
    NotificationKind kind,
    PublicUser who,
    DateTime at, {
    bool read = false,
  }) => AppNotification(
    id: id,
    kind: kind,
    isRead: read,
    createdAt: at,
    actor: who,
    postId: 'p1',
  );
  return [
    n('n1', NotificationKind.postCommented, tamara, _ago(minutes: 2)),
    n('n2', NotificationKind.postSparked, chisomo, _ago(minutes: 9)),
    n('n3', NotificationKind.circleNewPost, grace, _ago(minutes: 31)),
    n(
      'n4',
      NotificationKind.friendPosted,
      kondwani,
      _ago(hours: 2),
      read: true,
    ),
    n(
      'n5',
      NotificationKind.commentReplied,
      kondwani,
      _ago(hours: 3),
      read: true,
    ),
    n(
      'n6',
      NotificationKind.newFollower,
      suggestions[0],
      _ago(hours: 5),
      read: true,
    ),
  ];
}

Widget notificationsPage() => const NotificationsPage();

/// The banner a comment brings in while you are in the app.
void showCommentBanner(ProviderContainer c) {
  c
      .read(inAppBannerProvider)
      .show(
        label: NotificationKind.postCommented.bannerLabel,
        icon: notificationIcon(NotificationKind.postCommented),
        accent: notificationAccent(NotificationKind.postCommented),
        title: tamara.displayName,
        body: 'Commented on your post',
        avatar: avatarImage(tamara.profilePic),
      );
}

// ------------------------------------------- draw together, the story ---

/// What the conversation with Tamara shows: normally [conversation]; for the
/// Draw Together story, the finished drawing is added as the newest message.
List<LocalMessage> Function() messagesInChat = conversation;

/// The drawing, sent to the chat as a picture (the file the app's own
/// "Send to chat" makes), as the newest message.
List<LocalMessage> conversationWithDrawing(String drawingPath) => [
  LocalMessage()
    ..messageId = 'm10'
    ..roomId = tamaraRoom
    ..senderId = me
    ..recipientId = tamara.id
    ..type = MessageType.image
    ..localMediaPath = drawingPath
    ..status = MessageStatus.read
    ..timestamp = _ago(minutes: 1),
  ...conversation(),
];

/// The finished drawing as strokes, for the app's scribble renderer.
List<Stroke> finishedDrawing() => [
  for (final line in drawingAt(1))
    Stroke(
      color: Color(line['c'] as int),
      width: (line['w'] as num).toDouble(),
      erase: false,
      points: [
        for (var i = 0; i + 1 < (line['p'] as List).length; i += 2)
          Offset(
            ((line['p'] as List)[i] as num).toDouble(),
            ((line['p'] as List)[i + 1] as num).toDouble(),
          ),
      ],
    ),
];

/// You, as Tamara's phone knows you: for shots of her side.
final meAsFriend = PublicUser(
  id: me,
  username: 'daylight',
  displayName: 'Daylight',
  profilePic: _img('limbani'),
  friendStatus: FriendStatus.friends,
);

/// Opens the same live canvas on Tamara's phone: the peer is you.
void startDrawingAsTamara(ProviderContainer c, double t) {
  final draw = c.read(drawTogetherProvider.notifier);
  if (c.read(drawTogetherProvider) == null) {
    draw.expectInvite(session: 'S', peerId: me);
  }
  draw.heard({
    'type': 'draw',
    'op': 'state',
    'session': 'S',
    'peer_id': me,
    'status': 'live',
    'paper': 2,
    'strokes': drawingAt(t),
  });
}

/// The banner a Draw Together invitation brings, as the app shows it.
void showDrawInviteBanner(ProviderContainer c) {
  c
      .read(inAppBannerProvider)
      .show(
        label: 'DRAW TOGETHER',
        icon: Icons.draw_outlined,
        title: tamara.displayName,
        body: 'wants to draw together',
        avatar: avatarImage(tamara.profilePic),
      );
}
