import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/auth/auth_repository.dart';
import 'package:agentmux_mobile/core/auth/token_storage.dart';
import 'package:dio/dio.dart';

/// Placeholders only: this is a public repo.
const testRelay = 'https://relay.example.test';
const testAuthDomain = 'auth.example.test';
const testClientId = 'test-mobile-client';

/// A JWT with [claims] as its payload and a dummy signature.
String fakeJwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'none'})}.${seg(claims)}.sig';
}

/// In-memory [TokenStorage]; [log] records `clear`.
class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage([this.log]);
  final List<String>? log;
  final values = <String, String>{};

  @override
  Future<void> save({
    required String idToken,
    required String accessToken,
    required String refreshToken,
    required DateTime expiry,
    required String userSub,
  }) async {
    values
      ..['id'] = idToken
      ..['access'] = accessToken
      ..['refresh'] = refreshToken
      ..['expiry'] = expiry.millisecondsSinceEpoch.toString()
      ..['sub'] = userSub;
  }

  @override
  Future<String?> readIdToken() async => values['id'];
  @override
  Future<String?> readAccessToken() async => values['access'];
  @override
  Future<String?> readRefreshToken() async => values['refresh'];
  @override
  Future<String?> readUserSub() async => values['sub'];

  @override
  Future<DateTime?> readExpiry() async {
    final v = values['expiry'];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(v));
  }

  @override
  Future<bool> hasTokens() async =>
      values['id'] != null && values['refresh'] != null;

  @override
  Future<String?> readBillingTier() async =>
      values['id'] == null ? null : idTokenClaim(values['id']!, 'billing_tier');

  @override
  Future<String?> readEmail() async =>
      values['id'] == null ? null : idTokenClaim(values['id']!, 'email');

  @override
  Future<void> clear() async {
    log?.add('clear');
    values.clear();
  }
}

class FakeRequest {
  FakeRequest(this.method, this.uri, this.body);
  final String method;
  final Uri uri;
  final String body;

  Map<String, String> get form => Uri.splitQueryString(body);
}

/// A canned answer; [offline] means the connection fails instead.
class FakeAnswer {
  const FakeAnswer(this.status, [this.body = const {}]) : offline = false;
  const FakeAnswer.offline() : status = 0, body = null, offline = true;
  final int status;
  final Object? body;
  final bool offline;
}

/// Answers by path; records every request (and `METHOD path` in [log]).
class RouteAdapter implements HttpClientAdapter {
  RouteAdapter(this.routes, [this.log]);
  final Map<String, FakeAnswer> routes;
  final List<String>? log;
  final requests = <FakeRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    requests.add(FakeRequest(options.method, options.uri, utf8.decode(bytes)));
    log?.add('${options.method} ${options.uri.path}');
    final answer = routes[options.uri.path] ?? const FakeAnswer(404);
    if (answer.offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(answer.body),
      answer.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Stands in for the system browser session.
class FakeBrowser {
  FakeBrowser([this.log]);
  final List<String>? log;
  final calls = <({Uri url, String scheme})>[];

  /// Answers a call with the callback URL; may throw.
  String Function(Uri url) answer =
      (url) =>
          'agentmuxmobile://auth/callback?code=abc'
          '&state=${url.queryParameters['state']}';

  Future<String> authenticate({
    required String url,
    required String callbackUrlScheme,
  }) async {
    final uri = Uri.parse(url);
    calls.add((url: uri, scheme: callbackUrlScheme));
    log?.add('browser ${uri.path}');
    return answer(uri);
  }
}

/// An [AuthRepository] for widget tests: no browser, no network.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.signedIn = false,
    this.email,
    this.available = true,
  });

  bool signedIn;
  String? email;
  bool? available;
  final signIns = <SignInMethod>[];
  Completer<void>? pendingSignIn;
  Object? signInError;
  int signOuts = 0;

  @override
  Future<bool?> signInAvailable() async => available;

  @override
  Future<void> signIn({SignInMethod method = SignInMethod.email}) async {
    signIns.add(method);
    final pending = pendingSignIn;
    if (pending != null) await pending.future;
    final error = signInError;
    if (error != null) throw error;
    signedIn = true;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    signedIn = false;
  }

  @override
  Future<bool> isAuthenticated() async => signedIn;

  @override
  Future<String?> getAccountEmail() async => signedIn ? email : null;

  @override
  Future<String> getValidAccessToken() async => 'access';

  @override
  Future<String> refreshTokens() async => 'access';

  @override
  Future<String?> getUserSub() async => null;
}
