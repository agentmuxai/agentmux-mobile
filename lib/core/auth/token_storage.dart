import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kIdToken = 'muxbus_id_token';
const _kRefreshToken = 'muxbus_refresh_token';
const _kTokenExpiry = 'muxbus_token_expiry';
const _kUserSub = 'muxbus_user_sub';

class TokenStorage {
  final _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> save({
    required String idToken,
    required String refreshToken,
    required DateTime expiry,
    required String userSub,
  }) async {
    await Future.wait([
      _store.write(key: _kIdToken, value: idToken),
      _store.write(key: _kRefreshToken, value: refreshToken),
      _store.write(key: _kTokenExpiry, value: expiry.millisecondsSinceEpoch.toString()),
      _store.write(key: _kUserSub, value: userSub),
    ]);
  }

  Future<String?> readIdToken() => _store.read(key: _kIdToken);
  Future<String?> readRefreshToken() => _store.read(key: _kRefreshToken);
  Future<String?> readUserSub() => _store.read(key: _kUserSub);

  Future<DateTime?> readExpiry() async {
    final v = await _store.read(key: _kTokenExpiry);
    if (v == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(v));
  }

  Future<bool> hasTokens() async {
    final t = await readIdToken();
    return t != null && t.isNotEmpty;
  }

  Future<void> clear() async {
    await Future.wait([
      _store.delete(key: _kIdToken),
      _store.delete(key: _kRefreshToken),
      _store.delete(key: _kTokenExpiry),
      _store.delete(key: _kUserSub),
    ]);
  }
}
