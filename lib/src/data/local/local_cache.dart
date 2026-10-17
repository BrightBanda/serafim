import 'dart:convert';

import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_user.dart';
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

  // --- housekeeping ---------------------------------------------------------

  /// Forgets everything stored for [account] (sign-out, or the account is gone).
  Future<void> clear(String account) async {
    final prefix = '$_version.$account.';
    for (final key
        in _prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await _prefs.remove(key);
    }
  }
}
