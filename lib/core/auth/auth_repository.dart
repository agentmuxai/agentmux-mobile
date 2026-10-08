import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../api/muxbus_api_base.dart';
import 'auth_errors.dart';
import 'muxbus_auth_config.dart';
import 'token_storage.dart';

export 'auth_errors.dart';

// Development overrides, injected via --dart-define. A release build leaves
// them empty and reads the cloud discovery document instead.
const _cognitoDomain = String.fromEnvironment('MUXBUS_COGNITO_DOMAIN');
const _clientId = String.fromEnvironment('MUXBUS_CLIENT_ID');
// agentmuxmobile:// scheme avoids conflicts with any existing agentmux:// desktop scheme.
const _redirectUri = 'agentmuxmobile://auth/callback';
const _logoutUri = 'agentmuxmobile://auth/logout';
const _callbackScheme = 'agentmuxmobile';

/// How the person signs in.
enum SignInMethod {
  /// Straight to Google: the sign-in service skips its own page.
  google,

  /// The sign-in service's own page (email and password).
  email,
}

/// Opens [url] in the system browser session and completes with the callback
/// URL. Throws a `PlatformException` with code `CANCELED` when the person
/// closes it. Replaced in tests.
typedef WebAuthenticate =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
    });

Future<String> _flutterWebAuth({
  required String url,
  required String callbackUrlScheme,
}) => FlutterWebAuth2.authenticate(
  url: url,
  callbackUrlScheme: callbackUrlScheme,
);

/// The sign-in service's authorize URL (PKCE S256). [method] google adds
/// `identity_provider=Google`; email leaves it out so the hosted page shows.
Uri buildAuthorizeUrl({
  required MuxbusAuthConfig config,
  required String codeChallenge,
  required String state,
  required SignInMethod method,
}) => Uri.https(config.domain, '/oauth2/authorize', {
  'response_type': 'code',
  'client_id': config.clientId,
  'redirect_uri': _redirectUri,
  'scope': 'openid email profile',
  'code_challenge': codeChallenge,
  'code_challenge_method': 'S256',
  'state': state,
  if (method == SignInMethod.google) 'identity_provider': 'Google',
});

/// The authorization code from a sign-in callback. Refuses a callback whose
/// `state` is not [expectedState] ([AuthStateMismatch]), reports `error`
/// ([AuthCallbackError]), and refuses one without a code.
String parseAuthCallback(String callbackUrl, {required String expectedState}) {
  final Uri uri;
  try {
    uri = Uri.parse(callbackUrl);
  } on FormatException {
    throw AuthException('Unreadable sign-in callback');
  }
  final params = uri.queryParameters;
  if (params['state'] != expectedState) throw AuthStateMismatch();
  final error = params['error'];
  if (error != null && error.isNotEmpty) {
    throw AuthCallbackError(error, params['error_description']);
  }
  final code = params['code'];
  if (code == null || code.isEmpty) {
    throw AuthException('No authorization code in the sign-in callback');
  }
  return code;
}

class AuthRepository {
  AuthRepository(
    this._storage, {
    Dio? dio,
    WebAuthenticate? authenticate,
    MuxbusAuthConfigSource? config,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ),
       _authenticate = authenticate ?? _flutterWebAuth {
    _config =
        config ??
        MuxbusAuthConfigSource(
          dio: _dio,
          apiBase: muxbusApiBase,
          domainOverride: _cognitoDomain,
          clientIdOverride: _clientId,
        );
  }

  final TokenStorage _storage;
  final Dio _dio;
  final WebAuthenticate _authenticate;
  late final MuxbusAuthConfigSource _config;

  // ── Sign in ──────────────────────────────────────────────────────────────

  /// Whether this build can sign in at all: false when no client id is
  /// configured anywhere, null when that can't be told right now (offline).
  Future<bool?> signInAvailable() => _config.available();

  /// Signs in through the system browser. Throws [AuthCancelled] when the
  /// person closes it, and another [AuthException] when it fails.
  Future<void> signIn({SignInMethod method = SignInMethod.email}) async {
    final config = await _config.resolve();
    // The verifier and state live only in this call (spec 4.7).
    final verifier = _generateCodeVerifier();
    final state = _generateState();
    final authUrl = buildAuthorizeUrl(
      config: config,
      codeChallenge: _generateCodeChallenge(verifier),
      state: state,
      method: method,
    );

    final String result;
    try {
      result = await _authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: _callbackScheme,
      );
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw AuthCancelled();
      throw AuthException('The browser sign-in failed (${e.code})');
    }

    final code = parseAuthCallback(result, expectedState: state);
    await _exchangeCode(config, code, verifier);
  }

  // ── Sign out ─────────────────────────────────────────────────────────────

  /// Revokes the refresh token (best effort), clears the stored session, then
  /// ends the hosted sign-in session in the browser without waiting for it,
  /// so the next "Connect with Google" really asks.
  Future<void> signOut() async {
    // Read the session before clearing it.
    String? refreshToken;
    try {
      refreshToken = await _storage.readRefreshToken();
    } catch (_) {}

    MuxbusAuthConfig? config;
    if (refreshToken != null) {
      try {
        config = await _config.resolve();
      } catch (_) {}
    }
    if (config != null) {
      try {
        await _dio.postUri<Object>(
          Uri.https(config.domain, '/oauth2/revoke'),
          data: {'token': refreshToken, 'client_id': config.clientId},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
      } catch (_) {
        // Ignored: the tokens are cleared below either way.
      }
    }

    await _storage.clear();

    if (config != null) unawaited(_endHostedSession(config));
  }

  Future<void> _endHostedSession(MuxbusAuthConfig config) async {
    try {
      await _authenticate(
        url:
            Uri.https(config.domain, '/logout', {
              'client_id': config.clientId,
              'logout_uri': _logoutUri,
            }).toString(),
        callbackUrlScheme: _callbackScheme,
      );
    } catch (_) {
      // Best effort: the local session is already gone.
    }
  }

  // ── Token access ─────────────────────────────────────────────────────────

  /// The bearer token for the relay: the Cognito **access** token. The relay
  /// accepts only access tokens (an ID token is refused as unauthorised), so
  /// every MuxBus call and the socket use this.
  Future<String> getValidAccessToken() async {
    final expiry = await _storage.readExpiry();
    final accessToken = await _storage.readAccessToken();

    if (await _storage.readRefreshToken() == null) {
      throw AuthException('Not authenticated');
    }

    // Refresh 60 seconds before actual expiry to avoid edge-case 401s. A
    // session saved before the access token was stored has none: refresh.
    final needsRefresh =
        accessToken == null ||
        expiry == null ||
        DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 60)));

    if (needsRefresh) return refreshTokens();
    return accessToken;
  }

  /// Refreshes the session and returns the new access token.
  Future<String> refreshTokens() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) throw AuthException('No refresh token');
    final config = await _config.resolve();

    final response = await _dio.postUri<Map<String, dynamic>>(
      Uri.https(config.domain, '/oauth2/token'),
      data: {
        'grant_type': 'refresh_token',
        'client_id': config.clientId,
        'refresh_token': refreshToken,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );

    await _saveTokenResponse(
      response.data!,
      // Cognito does not issue a new refresh token on refresh — reuse existing.
      existingRefreshToken: refreshToken,
    );

    return (await _storage.readAccessToken())!;
  }

  Future<String?> getUserSub() => _storage.readUserSub();

  /// The signed-in account's email, from the stored ID token.
  Future<String?> getAccountEmail() => _storage.readEmail();

  Future<bool> isAuthenticated() => _storage.hasTokens();

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _exchangeCode(
    MuxbusAuthConfig config,
    String code,
    String verifier,
  ) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.postUri<Map<String, dynamic>>(
        Uri.https(config.domain, '/oauth2/token'),
        data: {
          'grant_type': 'authorization_code',
          'client_id': config.clientId,
          'redirect_uri': _redirectUri,
          'code': code,
          'code_verifier': verifier,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (e) {
      if (e.response == null) throw AuthNetworkError();
      throw AuthException(
        'The sign-in service refused the code (${e.response!.statusCode})',
      );
    }
    await _saveTokenResponse(response.data!);
  }

  Future<void> _saveTokenResponse(
    Map<String, dynamic> data, {
    String? existingRefreshToken,
  }) async {
    final idToken = data['id_token'] as String?;
    final accessToken = data['access_token'] as String?;
    final refreshToken =
        (data['refresh_token'] as String?) ?? existingRefreshToken;
    final expiresIn = data['expires_in'] as int? ?? 3600;

    if (idToken == null || accessToken == null || refreshToken == null) {
      throw AuthException('Incomplete token response');
    }

    final sub = _extractSub(idToken);
    final expiry = DateTime.now().add(Duration(seconds: expiresIn));

    await _storage.save(
      idToken: idToken,
      accessToken: accessToken,
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
    return base64UrlEncode(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    ).replaceAll('=', '');
  }
}
