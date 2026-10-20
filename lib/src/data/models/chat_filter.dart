/// A filter on the chat list: All, Friends, Unread, Groups, or one the
/// person made themselves.
enum ChatFilterKind { all, friends, unread, groups, custom }

/// A named set of chats.
///
/// The four built-ins are constants, so a saved selection still means
/// something after the app is updated. A custom filter is a set of room ids
/// the person picked.
class ChatFilter {
  const ChatFilter({
    required this.id,
    required this.name,
    required this.kind,
    this.roomIds = const {},
  });

  static const all = ChatFilter(
    id: 'all',
    name: 'All',
    kind: ChatFilterKind.all,
  );
  static const friends = ChatFilter(
    id: 'friends',
    name: 'Friends',
    kind: ChatFilterKind.friends,
  );
  static const unread = ChatFilter(
    id: 'unread',
    name: 'Unread',
    kind: ChatFilterKind.unread,
  );
  static const groups = ChatFilter(
    id: 'groups',
    name: 'Groups',
    kind: ChatFilterKind.groups,
  );

  /// The built-ins, in the order they are shown.
  static const builtIns = [all, friends, unread, groups];

  final String id;
  final String name;
  final ChatFilterKind kind;

  /// The chats in a custom filter, by room id. Empty for the built-ins.
  final Set<String> roomIds;

  bool get isCustom => kind == ChatFilterKind.custom;

  /// The name shown on the chip and as the heading above the list.
  String get label => name;

  ChatFilter copyWith({String? name, Set<String>? roomIds}) => ChatFilter(
    id: id,
    name: name ?? this.name,
    kind: kind,
    roomIds: roomIds ?? this.roomIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (roomIds.isNotEmpty) 'room_ids': roomIds.toList(),
  };

  factory ChatFilter.fromJson(Map<String, dynamic> json) => ChatFilter(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    kind: ChatFilterKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ChatFilterKind.custom,
    ),
    roomIds: {
      for (final r in (json['room_ids'] as List? ?? const [])) r.toString(),
    },
  );
}
