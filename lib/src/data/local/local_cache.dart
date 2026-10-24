import 'dart:convert';

import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/data/models/chat_filter.dart';
import 'package:serafim/src/data/models/group.dart';
import 'package:serafim/src/data/models/link_preview.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the profile cache holds. A profile of `null` is meaningful: it means
/// "the server said this person has not made one yet", which is different from
/// "nothing is cached".
class CachedProfile {
  const CachedProfile(this.profile);
  final Profile? profile;
}

/// A copy of the signed-in person's own data, kept on the phone so the app can
/// open straight into the chat list without waiting for the server — the way
/// WhatsApp does. The network refreshes it in the background.
///
/// Stored in [SharedPreferences], which `main()` loads before the first frame,
/// so reads are instant and synchronous. Everything is keyed by account id, so
/// two people using one phone never see each other's data, and a corrupt entry
/// simply reads as "not cached".
class LocalCache {
  LocalCache(this._prefs);

  final SharedPreferences _prefs;

  static const _version = 'cache.v1';

  String _key(String account, String name) => '$_version.$account.$name';

  T? _read<T>(String key, T Function(Object? json) decode) {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return null;
      return decode(jsonDecode(raw));
    } catch (_) {
      _prefs.remove(key); // Corrupt or from an incompatible version.
      return null;
    }
  }

  Future<void> _write(String key, Object? json) =>
      _prefs.setString(key, jsonEncode(json));

  // --- the account itself ---------------------------------------------------

  AppUser? user(String account) => _read(
    _key(account, 'user'),
    (j) => AppUser.fromJson(j! as Map<String, dynamic>),
  );

  Future<void> saveUser(AppUser user) =>
      _write(_key(user.id, 'user'), user.toJson());

  // --- their profile --------------------------------------------------------

  CachedProfile? profile(String account) =>
      _read(_key(account, 'profile'), (j) {
        final map = j! as Map<String, dynamic>;
        return CachedProfile(
          map['profile'] is Map<String, dynamic>
              ? Profile.fromJson(map['profile'] as Map<String, dynamic>)
              : null,
        );
      });

  Future<void> saveProfile(String account, Profile? profile) =>
      _write(_key(account, 'profile'), {'profile': profile?.toJson()});

  // --- friends --------------------------------------------------------------

  List<PublicUser>? friends(String account) => _read(
    _key(account, 'friends'),
    (j) => [
      for (final e in j! as List)
        PublicUser.fromJson(e as Map<String, dynamic>),
    ],
  );

  Future<void> saveFriends(String account, List<PublicUser> friends) =>
      _write(_key(account, 'friends'), [for (final f in friends) f.toJson()]);

  // --- people you follow (ids only: enough to label a post's Follow button
  // correctly before the network answers) ------------------------------------

  Set<String>? followingIds(String account) => _read(
    _key(account, 'followingIds'),
    (j) => {for (final e in j! as List) e as String},
  );

  Future<void> saveFollowingIds(String account, Iterable<String> ids) =>
      _write(_key(account, 'followingIds'), ids.toList());

  // --- everyone else you have seen (for people you chat with but are not
  // friends with, so their name and photo show instantly) ---------------------

  Map<String, PublicUser> _people(String account) =>
      _read(_key(account, 'people'), (j) {
        final map = j! as Map<String, dynamic>;
        return {
          for (final e in map.entries)
            e.key: PublicUser.fromJson(e.value as Map<String, dynamic>),
        };
      }) ??
      {};

  PublicUser? person(String account, String id) => _people(account)[id];

  /// The people named as Wings (up to six), as last known.
  List<PublicUser>? wings(String account) => _read(
    _key(account, 'wings'),
    (j) => [
      for (final e in j! as List)
        PublicUser.fromJson(e as Map<String, dynamic>),
    ],
  );

  Future<void> saveWings(String account, List<PublicUser> wings) =>
      _write(_key(account, 'wings'), [for (final w in wings) w.toJson()]);

  Future<void> savePerson(String account, PublicUser person) {
    final people = _people(account)..[person.id] = person;
    return _write(_key(account, 'people'), {
      for (final e in people.entries) e.key: e.value.toJson(),
    });
  }

  // --- the official SERAFIM chat ------------------------------------------

  /// The announcements last fetched, newest first, so the official chat opens
  /// instantly and works offline.
  List<Announcement>? announcements(String account) => _read(
    _key(account, 'announcements'),
    (j) => [
      for (final e in j! as List)
        Announcement.fromJson(e as Map<String, dynamic>),
    ],
  );

  Future<void> saveAnnouncements(String account, List<Announcement> items) =>
      _write(_key(account, 'announcements'), [
        for (final a in items) a.toJson(),
      ]);

  /// When this person last looked at the official chat (for its unread dot).
  DateTime? officialLastRead(String account) => _read(
    _key(account, 'officialLastRead'),
    (j) => DateTime.parse(j! as String).toUtc(),
  );

  Future<void> saveOfficialLastRead(String account, DateTime at) =>
      _write(_key(account, 'officialLastRead'), at.toUtc().toIso8601String());

  // --- groups ---------------------------------------------------------------

  List<GroupSummary>? groups(String account) => _read(
    _key(account, 'groups'),
    (j) => [
      for (final e in j! as List)
        GroupSummary.fromJson(e as Map<String, dynamic>),
    ],
  );

  Future<void> saveGroups(String account, List<GroupSummary> groups) =>
      _write(_key(account, 'groups'), [for (final g in groups) g.toJson()]);

  /// When this person last acknowledged each group's rules, by group id.
  Map<String, DateTime> rulesSeen(String account) =>
      _read(
        _key(account, 'rulesSeen'),
        (j) => (j! as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, DateTime.parse(v as String).toUtc()),
        ),
      ) ??
      {};

  Future<void> saveRulesSeen(String account, Map<String, DateTime> seen) =>
      _write(
        _key(account, 'rulesSeen'),
        seen.map((k, v) => MapEntry(k, v.toUtc().toIso8601String())),
      );

  // --- stickers -------------------------------------------------------------

  /// Recently sent sticker ids, most recent first.
  List<String> recentStickers(String account) =>
      _read(
        _key(account, 'recentStickers'),
        (j) => [for (final e in j! as List) e as String],
      ) ??
      const [];

  Future<void> saveRecentStickers(String account, List<String> ids) =>
      _write(_key(account, 'recentStickers'), ids);

  // --- link previews --------------------------------------------------------

  static const _maxPreviews = 150;

  /// Saved previews by URL. A null value means "the server had nothing", so
  /// the same dead link is not asked about again and again.
  Map<String, LinkPreview?> _previews() =>
      _read('$_version.linkPreviews', (j) {
        final map = j! as Map<String, dynamic>;
        return {
          for (final e in map.entries)
            e.key: e.value == null
                ? null
                : LinkPreview.fromJson(e.value as Map<String, dynamic>),
        };
      }) ??
      {};

  /// (found, preview): found is false when nothing is saved for [url].
  (bool, LinkPreview?) linkPreview(String url) {
    final all = _previews();
    return (all.containsKey(url), all[url]);
  }

  Future<void> saveLinkPreview(String url, LinkPreview? preview) {
    final all = _previews()
      ..remove(url)
      ..[url] = preview;
    // Oldest first in insertion order: drop from the front.
    while (all.length > _maxPreviews) {
      all.remove(all.keys.first);
    }
    return _write('$_version.linkPreviews', {
      for (final e in all.entries) e.key: e.value?.toJson(),
    });
  }

  // --- chat backgrounds -----------------------------------------------------

  /// The background every chat uses unless it has its own (encoded
  /// `ChatWallpaper`).
  String? defaultWallpaper(String account) =>
      _prefs.getString(_key(account, 'wallpaper.default'));

  Future<void> saveDefaultWallpaper(String account, String? encoded) =>
      _setOrRemove(_key(account, 'wallpaper.default'), encoded);

  /// Per-chat backgrounds, by room id.
  Map<String, String> roomWallpapers(String account) =>
      _read(
        _key(account, 'wallpaper.rooms'),
        (j) => (j! as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as String),
        ),
      ) ??
      {};

  Future<void> saveRoomWallpapers(String account, Map<String, String> rooms) =>
      _write(_key(account, 'wallpaper.rooms'), rooms);

  // --- chat filters ---------------------------------------------------------

  /// The custom chat filters the person made. The built-in ones are
  /// constants and are never stored.
  List<ChatFilter>? chatFilters(String account) => _read(
    _key(account, 'chat_filters'),
    (j) => [
      for (final f in (j! as List))
        ChatFilter.fromJson(f as Map<String, dynamic>),
    ],
  );

  Future<void> saveChatFilters(String account, List<ChatFilter> filters) =>
      _write(_key(account, 'chat_filters'), [
        for (final f in filters) f.toJson(),
      ]);

  Future<void> _setOrRemove(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);

  // --- housekeeping ---------------------------------------------------------

  /// Chats the person removed from their list, by room id, with when. A chat
  /// comes back once something newer arrives in it.
  Map<String, DateTime> removedChats(String account) =>
      _read(_key(account, 'removedChats'), (j) {
        final map = j! as Map<String, dynamic>;
        return {
          for (final e in map.entries)
            e.key: DateTime.fromMillisecondsSinceEpoch(e.value as int),
        };
      }) ??
      {};

  Future<void> saveRemovedChats(String account, Map<String, DateTime> rooms) =>
      _write(_key(account, 'removedChats'), {
        for (final e in rooms.entries) e.key: e.value.millisecondsSinceEpoch,
      });

  /// Forgets everything stored for [account] (sign-out, or the account is gone).
  Future<void> clear(String account) async {
    final prefix = '$_version.$account.';
    for (final key
        in _prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await _prefs.remove(key);
    }
  }
}
