import 'package:serafim/src/data/models/public_user.dart';

/// Who an Echo may reach. Friends always qualify; new people only if they
/// share an interest with you.
enum EchoAudience {
  everyone('Everyone', 'Friends and new people'),
  friends('Friends', 'Only your friends'),
  strangers('New people', 'People who share your interests');

  const EchoAudience(this.label, this.description);

  final String label;
  final String description;
}

/// An Echo: a short "I'm up for a chat" message broadcast to up to 30
/// people, as a notification and a push (backend `app/api/echos.py`, which
/// holds the rules). It can be answered for an hour.
class Echo {
  const Echo({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.expiresAt,
    required this.user,
    this.tag,
    this.ended = false,
    this.isFriend = false,
    this.sharedInterests = const [],
    this.responded = false,
    this.reachedCount = 0,
    this.responseCount = 0,
  });

  /// Longest text an Echo may have.
  static const textMax = 80;

  /// How many people one reaches at most.
  static const reach = 30;

  final String id;
  final String text;
  final String? tag;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// Who sent it.
  final PublicUser user;

  /// It can't be answered any more.
  final bool ended;
  final bool isFriend;

  /// Interest categories you share with the sender.
  final List<String> sharedInterests;

  /// You answered it already.
  final bool responded;
  final int reachedCount;
  final int responseCount;

  /// Minutes left to answer, 0 once it has ended.
  int minutesLeft(DateTime now) {
    if (ended) return 0;
    final left = expiresAt.difference(now).inSeconds;
    return left <= 0 ? 0 : (left / 60).ceil();
  }

  factory Echo.fromJson(Map<String, dynamic> json) => Echo(
    id: json['id'].toString(),
    text: json['text'] as String,
    tag: json['tag'] as String?,
    createdAt: _time(json['created_at']),
    expiresAt: _time(json['expires_at']),
    user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
    ended: json['ended'] as bool? ?? false,
    isFriend: json['is_friend'] as bool? ?? false,
    sharedInterests: [
      for (final i in (json['shared_interests'] as List? ?? const []))
        i.toString(),
    ],
    responded: json['responded'] as bool? ?? false,
    reachedCount: json['reached_count'] as int? ?? 0,
    responseCount: json['response_count'] as int? ?? 0,
  );
}

/// Your latest Echo, and what the limits allow now.
class MyEchoStatus {
  const MyEchoStatus({
    this.echo,
    this.sentToday = 0,
    this.perDay = 3,
    this.nextAllowedAt,
  });

  final Echo? echo;
  final int sentToday;
  final int perDay;

  /// When the next may be sent, if there is a pause after the last one.
  final DateTime? nextAllowedAt;

  bool get dailyLimitReached => sentToday >= perDay;

  factory MyEchoStatus.fromJson(Map<String, dynamic> json) => MyEchoStatus(
    echo: json['echo'] is Map<String, dynamic>
        ? Echo.fromJson(json['echo'] as Map<String, dynamic>)
        : null,
    sentToday: json['sent_today'] as int? ?? 0,
    perDay: json['per_day'] as int? ?? 3,
    nextAllowedAt: json['next_allowed_at'] is String
        ? DateTime.tryParse(json['next_allowed_at'] as String)?.toUtc()
        : null,
  );
}

DateTime _time(Object? raw) =>
    (raw is String ? DateTime.tryParse(raw)?.toUtc() : null) ??
    DateTime.now().toUtc();
