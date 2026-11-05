import 'package:dio/dio.dart';
import 'package:serafim/src/core/network/api_exception.dart';

/// Features of one conversation, shared by everyone in it. In a 1:1 chat
/// either person may change them; in a group, only the owner and admins.
class ChatFeatures {
  const ChatFeatures({
    this.hideDeleted = false,
    this.updatedBy,
    this.updatedAt,
    this.canEdit = true,
  });

  /// Deleted messages vanish instead of showing "This message was deleted".
  final bool hideDeleted;

  /// Who changed them last, and when.
  final String? updatedBy;
  final DateTime? updatedAt;

  /// Whether you may change them.
  final bool canEdit;

  static const defaults = ChatFeatures();

  ChatFeatures copyWith({bool? hideDeleted, bool? canEdit}) => ChatFeatures(
    hideDeleted: hideDeleted ?? this.hideDeleted,
    updatedBy: updatedBy,
    updatedAt: updatedAt,
    canEdit: canEdit ?? this.canEdit,
  );

  factory ChatFeatures.fromJson(Map<String, dynamic> json) => ChatFeatures(
    hideDeleted: json['hide_deleted'] == true,
    updatedBy: json['updated_by'] as String?,
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    canEdit: json['can_edit'] != false,
  );

  Map<String, dynamic> toJson() => {
    'hide_deleted': hideDeleted,
    'updated_by': updatedBy,
    'updated_at': updatedAt?.toIso8601String(),
    'can_edit': canEdit,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatFeatures &&
      other.hideDeleted == hideDeleted &&
      other.updatedBy == updatedBy &&
      other.updatedAt == updatedAt &&
      other.canEdit == canEdit;

  @override
  int get hashCode => Object.hash(hideDeleted, updatedBy, updatedAt, canEdit);
}

/// Which conversation: the other person in a 1:1 chat, or a group.
class ChatRef {
  const ChatRef.direct(this.id) : isGroup = false;
  const ChatRef.group(this.id) : isGroup = true;

  final String id;
  final bool isGroup;

  String get _path => isGroup ? '/chats/groups/$id' : '/chats/direct/$id';
}

/// One changed chat from the server's list.
typedef ChatFeaturesEntry = ({ChatRef chat, ChatFeatures features});

/// Talks to the backend's `/chats/.../settings` routes.
class ChatFeaturesService {
  const ChatFeaturesService(this._dio);

  final Dio _dio;

  /// Every chat of yours whose features differ from the defaults.
  Future<List<ChatFeaturesEntry>> all() async {
    try {
      final data = (await _dio.get<dynamic>('/chats/settings')).data;
      if (data is! List) return const [];
      return [
        for (final e in data)
          if (e is Map<String, dynamic>) entryOf(e),
      ];
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ChatFeatures> get(ChatRef chat) async => ChatFeatures.fromJson(
    await _map(() => _dio.get('${chat._path}/settings')),
  );

  Future<ChatFeatures> set(ChatRef chat, {required bool hideDeleted}) async =>
      ChatFeatures.fromJson(
        await _map(
          () => _dio.put(
            '${chat._path}/settings',
            data: {'hide_deleted': hideDeleted},
          ),
        ),
      );

  /// One entry as the server sends it (the list, and `chat_settings` frames).
  static ChatFeaturesEntry entryOf(Map<String, dynamic> json) {
    final id = json['id'].toString();
    return (
      chat: json['chat'] == 'group' ? ChatRef.group(id) : ChatRef.direct(id),
      features: ChatFeatures.fromJson(json),
    );
  }

  Future<Map<String, dynamic>> _map(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final data = (await request()).data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Something went wrong. Please try again.');
      }
      return data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
