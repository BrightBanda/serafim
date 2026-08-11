import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:serafim/src/data/models/auth_session.dart';

/// The single source of truth for "who is signed in".
///
/// Two very different callers read this: the auth interceptor, on every
/// outbound request (so reads must be synchronous and cheap), and the auth
/// view model, which needs to know when the session changes underneath it
/// — for example when the interceptor rotates a refresh token or gives up and
/// signs the user out. Hence the in-memory [current] plus the [changes] stream,
/// with the encrypted keystore as the slow durable backing.
class SessionStore {
  SessionStore(this._storage);

  static const _key = 'serafim.auth.session';

  final FlutterSecureStorage _storage;
  final StreamController<AuthSession?> _controller =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _current;

  /// The live session, or null when signed out. Synchronous by design.
  AuthSession? get current => _current;

  /// Emits on every write, including sign-out (which emits null).
  Stream<AuthSession?> get changes => _controller.stream;

  /// Loads the persisted session at startup. Returns null when there is none.
  ///
  /// A corrupt or unreadable entry is treated as "signed out" rather than an
  /// error — the worst case is the user signs in again.
  Future<AuthSession?> restore() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      _current = AuthSession.fromStorage(decoded);
    } catch (_) {
      await _storage.delete(key: _key);
      _current = null;
    }
    _controller.add(_current);
    return _current;
  }

  Future<void> save(AuthSession session) async {
    _current = session;
    _controller.add(session);
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    _current = null;
    _controller.add(null);
    await _storage.delete(key: _key);
  }

  void dispose() => _controller.close();
}
