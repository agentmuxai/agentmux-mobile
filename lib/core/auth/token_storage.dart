import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kIdToken = 'muxbus_id_token';
const _kAccessToken = 'muxbus_access_token';
const _kRefreshToken = 'muxbus_refresh_token';
const _kTokenExpiry = 'muxbus_token_expiry';
const _kUserSub = 'muxbus_user_sub';

/// A string claim from a JWT's payload, without checking the signature (the
/// token came from our own sign-in). Null when absent or unreadable.
String? idTokenClaim(String token, String name) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)))
        as Map<String, dynamic>;
    final v = decoded[name];
    return v is String ? v : null;
  } catch (_) {
    return null;
  }
}

class TokenStorage {
  final _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> save({
    required String idToken,
    required String accessToken,
    required String refreshToken,
    required DateTime expiry,
    required String userSub,
  }) async {
    await Future.wait([
      _store.write(key: _kIdToken, value: idToken),
      _store.write(key: _kAccessToken, value: accessToken),
      _store.write(key: _kRefreshToken, value: refreshToken),
      _store.write(key: _kTokenExpiry, value: expiry.millisecondsSinceEpoch.toString()),
      _store.write(key: _kUserSub, value: userSub),
    ]);
  }

  Future<String?> readIdToken() => _store.read(key: _kIdToken);
  Future<String?> readAccessToken() => _store.read(key: _kAccessToken);
  Future<String?> readRefreshToken() => _store.read(key: _kRefreshToken);
  Future<String?> readUserSub() => _store.read(key: _kUserSub);

  Future<DateTime?> readExpiry() async {
    final v = await _store.read(key: _kTokenExpiry);
    if (v == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(v));
  }

  // Requires both tokens — prevents crash when stale emulator state has
  // id_token but no refresh_token.
  Future<bool> hasTokens() async {
    final results = await Future.wait([readIdToken(), readRefreshToken()]);
    return results[0] != null && results[0]!.isNotEmpty &&
        results[1] != null && results[1]!.isNotEmpty;
  }

  // Decodes the billing_tier claim embedded by the Cognito pre-token Lambda.
  // No API call — reads straight from the stored JWT payload.
  Future<String?> readBillingTier() => _readIdClaim('billing_tier');

  /// The signed-in account's email (the ID token's `email` claim).
  Future<String?> readEmail() => _readIdClaim('email');

  Future<String?> _readIdClaim(String name) async {
    final token = await readIdToken();
    if (token == null) return null;
    return idTokenClaim(token, name);
  }

  Future<void> clear() async {
    await Future.wait([
      _store.delete(key: _kIdToken),
      _store.delete(key: _kAccessToken),
      _store.delete(key: _kRefreshToken),
      _store.delete(key: _kTokenExpiry),
      _store.delete(key: _kUserSub),
    ]);
  }
}
