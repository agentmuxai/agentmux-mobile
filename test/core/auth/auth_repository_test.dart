import 'dart:convert';

import 'package:agentmux_mobile/core/auth/auth_repository.dart';
import 'package:agentmux_mobile/core/auth/muxbus_auth_config.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_fakes.dart';

const _docPath = '/.well-known/agentmux-cloud.json';

final _tokenAnswer = FakeAnswer(200, {
  'id_token': fakeJwt({'sub': 'user-1', 'email': 'person@example.test'}),
  'access_token': 'access-1',
  'refresh_token': 'refresh-1',
  'expires_in': 900,
});

void main() {
  late List<String> log;
  late FakeTokenStorage storage;
  late RouteAdapter adapter;
  late FakeBrowser browser;
  late AuthRepository repo;

  void setUpRepo({
    FakeAnswer? doc,
    FakeAnswer? token,
    FakeAnswer revoke = const FakeAnswer(200),
  }) {
    log = [];
    storage = FakeTokenStorage(log);
    adapter = RouteAdapter({
      _docPath:
          doc ??
          const FakeAnswer(200, {
            'cognito': {
              'domain': 'https://$testAuthDomain',
              'mobileClientId': testClientId,
            },
          }),
      '/oauth2/token': token ?? _tokenAnswer,
      '/oauth2/revoke': revoke,
    }, log);
    browser = FakeBrowser(log);
    final dio = Dio()..httpClientAdapter = adapter;
    repo = AuthRepository(
      storage,
      dio: dio,
      authenticate: browser.authenticate,
      config: MuxbusAuthConfigSource(dio: dio, apiBase: testRelay),
    );
  }

  Future<void> signInSession() async {
    await storage.save(
      idToken: fakeJwt({'sub': 'user-1', 'email': 'person@example.test'}),
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      expiry: DateTime.now().add(const Duration(minutes: 10)),
      userSub: 'user-1',
    );
  }

  group('sign in', () {
    setUp(setUpRepo);

    test(
      'Google: straight to Google, PKCE S256, state, then the code exchange',
      () async {
        await repo.signIn(method: SignInMethod.google);

        final call = browser.calls.single;
        expect(call.scheme, 'agentmuxmobile');
        final url = call.url;
        expect(url.scheme, 'https');
        expect(url.host, testAuthDomain);
        expect(url.path, '/oauth2/authorize');
        final q = url.queryParameters;
        expect(q['identity_provider'], 'Google');
        expect(q['response_type'], 'code');
        expect(q['client_id'], testClientId);
        expect(q['redirect_uri'], 'agentmuxmobile://auth/callback');
        expect(q['scope'], 'openid email profile');
        expect(q['code_challenge_method'], 'S256');
        expect(q['state'], isNotEmpty);

        // The challenge is the S256 of the verifier sent with the code.
        final exchange = adapter.requests.singleWhere(
          (r) => r.uri.path == '/oauth2/token',
        );
        expect(exchange.uri.host, testAuthDomain);
        final form = exchange.form;
        expect(form['grant_type'], 'authorization_code');
        expect(form['code'], 'abc');
        expect(form['client_id'], testClientId);
        final verifier = form['code_verifier']!;
        expect(
          q['code_challenge'],
          base64UrlEncode(
            sha256.convert(utf8.encode(verifier)).bytes,
          ).replaceAll('=', ''),
        );

        expect(await repo.isAuthenticated(), isTrue);
        expect(await repo.getAccountEmail(), 'person@example.test');
        expect(await storage.readAccessToken(), 'access-1');
      },
    );

    test('email: the hosted page, no identity_provider', () async {
      await repo.signIn(method: SignInMethod.email);
      final q = browser.calls.single.url.queryParameters;
      expect(q.containsKey('identity_provider'), isFalse);
      expect(q['code_challenge_method'], 'S256');
    });

    test('a new state for every sign-in', () async {
      await repo.signIn(method: SignInMethod.email);
      await repo.signIn(method: SignInMethod.email);
      final states =
          browser.calls.map((c) => c.url.queryParameters['state']).toSet();
      expect(states, hasLength(2));
    });

    test(
      'a callback with another state is refused, and nothing is stored',
      () async {
        browser.answer =
            (_) => 'agentmuxmobile://auth/callback?code=abc&state=forged';
        await expectLater(
          repo.signIn(method: SignInMethod.google),
          throwsA(isA<AuthStateMismatch>()),
        );
        expect(
          adapter.requests.where((r) => r.uri.path == '/oauth2/token'),
          isEmpty,
        );
        expect(await repo.isAuthenticated(), isFalse);
      },
    );

    test('a callback without state is refused', () async {
      browser.answer = (_) => 'agentmuxmobile://auth/callback?code=abc';
      await expectLater(repo.signIn(), throwsA(isA<AuthStateMismatch>()));
    });

    test('a callback error is reported with its description', () async {
      browser.answer =
          (url) =>
              'agentmuxmobile://auth/callback'
              '?error=access_denied'
              '&error_description=PreSignUp+failed+with+error+Not+invited.'
              '&state=${url.queryParameters['state']}';
      await expectLater(
        repo.signIn(method: SignInMethod.google),
        throwsA(
          isA<AuthCallbackError>()
              .having((e) => e.error, 'error', 'access_denied')
              .having(
                (e) => e.description,
                'description',
                'PreSignUp failed with error Not invited.',
              )
              .having((e) => e.accountRefused, 'accountRefused', isTrue),
        ),
      );
      expect(await repo.isAuthenticated(), isFalse);
    });

    test('closing the browser is a cancel, not an error', () async {
      browser.answer = (_) => throw PlatformException(code: 'CANCELED');
      await expectLater(repo.signIn(), throwsA(isA<AuthCancelled>()));
      expect(await repo.isAuthenticated(), isFalse);
    });

    test('no client id: no browser is opened', () async {
      setUpRepo(doc: const FakeAnswer(200, {'cognito': {}}));
      await expectLater(repo.signIn(), throwsA(isA<AuthUnavailable>()));
      expect(browser.calls, isEmpty);
      expect(await repo.signInAvailable(), isFalse);
    });

    test('offline at the code exchange: a network error', () async {
      setUpRepo(token: const FakeAnswer.offline());
      await expectLater(repo.signIn(), throwsA(isA<AuthNetworkError>()));
      expect(await repo.isAuthenticated(), isFalse);
    });

    test(
      'refresh uses the same configuration and keeps the refresh token',
      () async {
        await signInSession();
        final token = await repo.refreshTokens();
        expect(token, 'access-1');
        final r = adapter.requests.singleWhere(
          (r) => r.uri.path == '/oauth2/token',
        );
        expect(r.uri.host, testAuthDomain);
        expect(r.form['grant_type'], 'refresh_token');
        expect(r.form['client_id'], testClientId);
        expect(r.form['refresh_token'], 'refresh-1');
      },
    );
  });

  group('parseAuthCallback', () {
    test('returns the code when the state matches', () {
      expect(
        parseAuthCallback(
          'agentmuxmobile://auth/callback?code=c1&state=s1',
          expectedState: 's1',
        ),
        'c1',
      );
    });

    test('state mismatch is refused before anything else is read', () {
      expect(
        () => parseAuthCallback(
          'agentmuxmobile://auth/callback?error=access_denied&state=other',
          expectedState: 's1',
        ),
        throwsA(isA<AuthStateMismatch>()),
      );
    });

    test('an error that is not a refusal', () {
      expect(
        () => parseAuthCallback(
          'agentmuxmobile://auth/callback?error=server_error&state=s1',
          expectedState: 's1',
        ),
        throwsA(
          isA<AuthCallbackError>()
              .having((e) => e.accountRefused, 'accountRefused', isFalse)
              .having((e) => e.description, 'description', isNull),
        ),
      );
    });

    test('no code and no error is a failure', () {
      expect(
        () => parseAuthCallback(
          'agentmuxmobile://auth/callback?state=s1',
          expectedState: 's1',
        ),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('readableAuthErrorDescription', () {
    test('drops the check prefix and ends as a sentence', () {
      expect(
        readableAuthErrorDescription('PreSignUp failed with error not invited'),
        'Not invited.',
      );
      expect(
        readableAuthErrorDescription('  user   is disabled  '),
        'User is disabled.',
      );
      expect(readableAuthErrorDescription('Already done!'), 'Already done!');
    });

    test('nothing to say is null', () {
      expect(readableAuthErrorDescription(null), isNull);
      expect(readableAuthErrorDescription('   '), isNull);
    });

    test('a long description is cut', () {
      final s = readableAuthErrorDescription('x' * 500)!;
      expect(s.length, lessThanOrEqualTo(201));
      expect(s.endsWith('…'), isTrue);
    });
  });

  group('sign out', () {
    test('revokes, then clears, then ends the hosted session', () async {
      setUpRepo();
      await signInSession();
      await repo.signOut();
      await pumpEventQueue();

      expect(log.where((e) => e != 'GET $_docPath').toList(), [
        'POST /oauth2/revoke',
        'clear',
        'browser /logout',
      ]);
      final revoke = adapter.requests.singleWhere(
        (r) => r.uri.path == '/oauth2/revoke',
      );
      expect(revoke.uri.host, testAuthDomain);
      expect(revoke.form, {'token': 'refresh-1', 'client_id': testClientId});

      final logout = browser.calls.single;
      expect(logout.scheme, 'agentmuxmobile');
      expect(logout.url.host, testAuthDomain);
      expect(logout.url.queryParameters, {
        'client_id': testClientId,
        'logout_uri': 'agentmuxmobile://auth/logout',
      });
      expect(await repo.isAuthenticated(), isFalse);
    });

    test('a failed revoke still clears the session', () async {
      setUpRepo(revoke: const FakeAnswer(500));
      await signInSession();
      await repo.signOut();
      expect(log, contains('clear'));
      expect(await repo.isAuthenticated(), isFalse);
    });

    test('offline: the session is still cleared', () async {
      setUpRepo(revoke: const FakeAnswer.offline());
      await signInSession();
      await repo.signOut();
      expect(await repo.isAuthenticated(), isFalse);
    });

    test('the hosted logout failing does not fail sign-out', () async {
      setUpRepo();
      browser.answer = (_) => throw PlatformException(code: 'CANCELED');
      await signInSession();
      await repo.signOut();
      await pumpEventQueue();
      expect(await repo.isAuthenticated(), isFalse);
    });

    test('no session: nothing to revoke, no browser, still cleared', () async {
      setUpRepo();
      await repo.signOut();
      expect(log, ['clear']);
      expect(browser.calls, isEmpty);
    });
  });
}
