import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/local/local_cache.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Profile profile({
  String name = 'Sam',
  List<String> interests = const ['Chess'],
}) => Profile(
  userId: 'u1',
  displayName: name,
  username: 'sam_n',
  profilePic: 'https://x/y.jpg',
  interests: interests,
  allowFriendRequests: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 2, 2),
);

PublicUser person(String id, {String name = 'Alex'}) => PublicUser(
  id: id,
  username: 'user_$id',
  displayName: name,
  profilePic: 'https://x/$id.jpg',
  interests: const ['Chess', 'Tea'],
  sharedInterests: const ['Chess'],
  friendStatus: FriendStatus.requestReceived,
  isFollowing: true,
  followsYou: true,
  acceptsFriendRequests: false,
  followerCount: 7,
  followingCount: 3,
);

Future<(LocalCache, SharedPreferences)> open([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return (LocalCache(prefs), prefs);
}

void main() {
  test('nothing is cached on a fresh install', () async {
    final (cache, _) = await open();
    expect(cache.user('u1'), isNull);
    expect(cache.profile('u1'), isNull);
    expect(cache.friends('u1'), isNull);
    expect(cache.person('u1', 'x'), isNull);
  });

  test('the account round-trips', () async {
    final (cache, _) = await open();
    await cache.saveUser(fakeUser(email: 'sam@example.com'));
    final user = cache.user('u1')!;
    expect(user.id, 'u1');
    expect(user.email, 'sam@example.com');
    expect(user.isActive, isTrue);
    expect(user.createdAt, DateTime.utc(2026, 1, 1));
  });

  test('a profile round-trips every field', () async {
    final (cache, _) = await open();
    await cache.saveProfile('u1', profile());
    final p = cache.profile('u1')!.profile!;
    expect(p.displayName, 'Sam');
    expect(p.username, 'sam_n');
    expect(p.profilePic, 'https://x/y.jpg');
    expect(p.interests, ['Chess']);
    expect(p.allowFriendRequests, isFalse);
    expect(p.updatedAt, DateTime.utc(2026, 2, 2));
  });

  test(
    '"no profile yet" is remembered, and is not the same as "nothing cached"',
    () async {
      final (cache, _) = await open();
      expect(cache.profile('u1'), isNull); // never fetched
      await cache.saveProfile('u1', null); // fetched: there isn't one
      expect(cache.profile('u1'), isNotNull);
      expect(cache.profile('u1')!.profile, isNull);
    },
  );

  test('friends round-trip with all their fields', () async {
    final (cache, _) = await open();
    await cache.saveFriends('u1', [
      person('a', name: 'Alex'),
      person('b', name: 'Bo'),
    ]);
    final friends = cache.friends('u1')!;
    expect(friends.map((f) => f.displayName), ['Alex', 'Bo']);
    final f = friends.first;
    expect(f.friendStatus, FriendStatus.requestReceived);
    expect(f.sharedInterests, ['Chess']);
    expect(f.isFollowing && f.followsYou, isTrue);
    expect(f.acceptsFriendRequests, isFalse);
    expect([f.followerCount, f.followingCount], [7, 3]);
  });

  test(
    'an empty friends list is cached too (zero friends is an answer)',
    () async {
      final (cache, _) = await open();
      await cache.saveFriends('u1', const []);
      expect(cache.friends('u1'), isEmpty);
    },
  );

  test('people accumulate and update by id', () async {
    final (cache, _) = await open();
    await cache.savePerson('u1', person('a', name: 'Old Name'));
    await cache.savePerson('u1', person('b'));
    await cache.savePerson('u1', person('a', name: 'New Name'));
    expect(cache.person('u1', 'a')!.displayName, 'New Name');
    expect(cache.person('u1', 'b'), isNotNull);
    expect(cache.person('u1', 'c'), isNull);
  });

  test('two accounts on one phone never see each other', () async {
    final (cache, _) = await open();
    await cache.saveUser(fakeUser(id: 'u1'));
    await cache.saveFriends('u1', [person('a')]);
    await cache.saveFriends('u2', [person('z')]);
    expect(cache.friends('u1')!.single.id, 'a');
    expect(cache.friends('u2')!.single.id, 'z');
    expect(cache.user('u2'), isNull);
  });

  test('clearing one account leaves the other alone', () async {
    final (cache, prefs) = await open();
    for (final id in ['u1', 'u2']) {
      await cache.saveUser(fakeUser(id: id));
      await cache.saveProfile(id, profile());
      await cache.saveFriends(id, [person('a')]);
      await cache.savePerson(id, person('a'));
    }
    await cache.clear('u1');
    expect(cache.user('u1'), isNull);
    expect(cache.profile('u1'), isNull);
    expect(cache.friends('u1'), isNull);
    expect(cache.person('u1', 'a'), isNull);
    expect(prefs.getKeys().where((k) => k.contains('.u1.')), isEmpty);
    expect(cache.user('u2'), isNotNull);
    expect(cache.friends('u2'), isNotNull);
  });

  test(
    'a corrupt or incompatible entry reads as "not cached" and is discarded',
    () async {
      final (cache, prefs) = await open({
        'cache.v1.u1.user': '{not json',
        'cache.v1.u1.friends': '"a string, not a list"',
        'cache.v1.u1.profile': '[1,2,3]',
      });
      expect(cache.user('u1'), isNull);
      expect(cache.friends('u1'), isNull);
      expect(cache.profile('u1'), isNull);
      expect(prefs.containsKey('cache.v1.u1.user'), isFalse);
    },
  );

  test('model JSON survives a round trip unchanged', () {
    final p = profile();
    expect(Profile.fromJson(p.toJson()).toJson(), p.toJson());
    final u = person('a');
    expect(PublicUser.fromJson(u.toJson()).toJson(), u.toJson());
    for (final s in FriendStatus.values) {
      expect(FriendStatus.parse(s.wire), s);
    }
  });
}
