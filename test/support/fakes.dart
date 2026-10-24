import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:serafim/src/data/models/app_user.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/models/auth_session.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/data/services/auth_service.dart';
import 'package:serafim/src/data/services/session_store.dart';
import 'package:serafim/src/data/services/social_service.dart';
import 'package:serafim/src/data/services/user_service.dart';

AuthSession fakeSession({
  String userId = 'u1',
  bool expired = false,
  String access = 'access-1',
  String refresh = 'refresh-1',
}) => AuthSession(
  accessToken: access,
  refreshToken: refresh,
  expiresAt: DateTime.now().toUtc().add(Duration(hours: expired ? -1 : 1)),
  userId: userId,
  email: '$userId@example.com',
);

AppUser fakeUser({String id = 'u1', String? email}) => AppUser(
  id: id,
  email: email ?? '$id@example.com',
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
);

/// An in-memory [SessionStore] (no keystore), with a log of what happened.
class FakeSessionStore extends SessionStore {
  FakeSessionStore([this._session]) : super(const FlutterSecureStorage());

  AuthSession? _session;
  final _changes = StreamController<AuthSession?>.broadcast();
  int clearCount = 0;
  Object? restoreError;

  @override
  AuthSession? get current => _session;

  @override
  Stream<AuthSession?> get changes => _changes.stream;

  @override
  Future<AuthSession?> restore() async {
    if (restoreError != null) throw restoreError!;
    return _session;
  }

  @override
  Future<void> save(AuthSession session) async {
    _session = session;
    _changes.add(session);
  }

  @override
  Future<void> clear() async {
    clearCount++;
    _session = null;
    _changes.add(null);
  }

  @override
  void dispose() => _changes.close();
}

/// `POST /auth/sync` with an answer you choose.
class FakeUserService extends UserService {
  FakeUserService(this.onSync) : super(Dio());

  Future<AppUser> Function() onSync;
  int syncCalls = 0;

  @override
  Future<AppUser> sync() {
    syncCalls++;
    return onSync();
  }
}

/// GoTrue with an answer you choose for `refresh`.
class FakeAuthService extends AuthService {
  FakeAuthService({this.onRefresh}) : super(Dio());

  Future<AuthSession> Function(String refreshToken)? onRefresh;
  int refreshCalls = 0;
  int signOutCalls = 0;

  @override
  Future<AuthSession> refresh(String refreshToken) {
    refreshCalls++;
    return onRefresh!(refreshToken);
  }

  @override
  Future<void> signOut(String accessToken) async => signOutCalls++;
}

/// A follow backend that remembers who you follow, like the server does.
/// [listGate], when set, holds back the following list until completed;
/// [failNext] makes the next follow or unfollow fail with that message.
class FakeFollowSocial extends SocialService {
  FakeFollowSocial([Iterable<String> followed = const []])
    : followed = {...followed},
      super(Dio());

  final Set<String> followed;
  final calls = <String>[];
  Completer<void>? listGate;
  String? failNext;

  @override
  Future<List<PublicUser>> following() async {
    await listGate?.future;
    return [
      for (final id in followed)
        PublicUser(id: id, username: id, displayName: id, isFollowing: true),
    ];
  }

  @override
  Future<void> follow(String userId) async {
    calls.add('follow $userId');
    _maybeFail();
    followed.add(userId);
  }

  @override
  Future<void> unfollow(String userId) async {
    calls.add('unfollow $userId');
    _maybeFail();
    followed.remove(userId);
  }

  void _maybeFail() {
    final message = failNext;
    failNext = null;
    if (message != null) throw ApiException(message);
  }
}
