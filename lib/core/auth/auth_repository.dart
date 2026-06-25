import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'token_storage.dart';

// Build-time constants injected via --dart-define.
const _cognitoDomain = String.fromEnvironment('MUXBUS_COGNITO_DOMAIN');
const _clientId = String.fromEnvironment('MUXBUS_CLIENT_ID');
// agentmuxmobile:// scheme avoids conflicts with any existing agentmux:// desktop scheme.
const _redirectUri = 'agentmuxmobile://auth/callback';
const _callbackScheme = 'agentmuxmobile';

class AuthRepository {
  AuthRepository(this._storage);

  final TokenStorage _storage;
  final _dio = Dio();

  // ── Sign in ──────────────────────────────────────────────────────────────

  Future<void> signIn() async {
    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);
    final state = _generateState();

    final authUrl = Uri.https(
      _cognitoDomain,
      '/oauth2/authorize',
      {
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'scope': 'openid email profile',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _callbackScheme,
    );

    final uri = Uri.parse(result);
    final code = uri.queryParameters['code'];
    if (code == null) throw AuthException('No authorization code in redirect');

    await _exchangeCode(code, verifier);
  }

  // ── Sign out ─────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _storage.clear();
    // Best-effort Cognito global sign-out (ignore errors — local clear is enough)
    try {
      final idToken = await _storage.readIdToken();
      if (idToken != null) {
        final logoutUrl = Uri.https(_cognitoDomain, '/logout', {
          'client_id': _clientId,
          'logout_uri': _redirectUri,
        });
        await _dio.getUri(logoutUrl);
      }
    } catch (_) {}
  }

  // ── Token access ─────────────────────────────────────────────────────────

  Future<String> getValidIdToken() async {
    final expiry = await _storage.readExpiry();
    final idToken = await _storage.readIdToken();

    if (idToken == null) throw AuthException('Not authenticated');

    // Refresh 60 seconds before actual expiry to avoid edge-case 401s.
    final needsRefresh = expiry == null ||
        DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 60)));

    if (needsRefresh) return refreshTokens();
    return idToken;
  }

  Future<String> refreshTokens() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) throw AuthException('No refresh token');

    final response = await _dio.postUri<Map<String, dynamic>>(
      Uri.https(_cognitoDomain, '/oauth2/token'),
      data: {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': refreshToken,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );

    await _saveTokenResponse(response.data!,
        // Cognito does not issue a new refresh token on refresh — reuse existing.
        existingRefreshToken: refreshToken);

    return (await _storage.readIdToken())!;
  }

  Future<String?> getUserSub() => _storage.readUserSub();

  Future<bool> isAuthenticated() => _storage.hasTokens();

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _exchangeCode(String code, String verifier) async {
    final response = await _dio.postUri<Map<String, dynamic>>(
      Uri.https(_cognitoDomain, '/oauth2/token'),
      data: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'code': code,
        'code_verifier': verifier,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );
    await _saveTokenResponse(response.data!);
  }

  Future<void> _saveTokenResponse(
    Map<String, dynamic> data, {
    String? existingRefreshToken,
  }) async {
    final idToken = data['id_token'] as String?;
    final refreshToken =
        (data['refresh_token'] as String?) ?? existingRefreshToken;
    final expiresIn = data['expires_in'] as int? ?? 3600;

    if (idToken == null || refreshToken == null) {
      throw AuthException('Incomplete token response');
    }

    final sub = _extractSub(idToken);
    final expiry = DateTime.now().add(Duration(seconds: expiresIn));

    await _storage.save(
      idToken: idToken,
      refreshToken: refreshToken,
      expiry: expiry,
      userSub: sub,
    );
  }

  String _extractSub(String idToken) {
    // JWT payload is the second segment, base64url-encoded.
    final parts = idToken.split('.');
    if (parts.length < 2) return '';
    final padded = base64.normalize(parts[1]);
    final payload = json.decode(utf8.decode(base64.decode(padded)));
    return (payload as Map<String, dynamic>)['sub'] as String? ?? '';
  }

  // PKCE helpers — RFC 7636
  String _generateCodeVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(43, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _generateState() {
    final rng = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}
