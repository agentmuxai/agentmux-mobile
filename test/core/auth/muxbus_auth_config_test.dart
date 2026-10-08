import 'package:agentmux_mobile/core/auth/auth_errors.dart';
import 'package:agentmux_mobile/core/auth/muxbus_auth_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_fakes.dart';

const _docPath = '/.well-known/agentmux-cloud.json';

Map<String, Object?> _doc({
  Object? domain = 'https://$testAuthDomain',
  Object? mobileClientId = testClientId,
}) => {
  'version': 1,
  'api': testRelay,
  'cognito': {
    'domain': domain,
    // The desktop's client: never used by the app.
    'clientId': 'test-desktop-client',
    'mobileClientId': mobileClientId,
  },
};

void main() {
  late RouteAdapter adapter;

  MuxbusAuthConfigSource make({
    FakeAnswer? answer,
    String domainOverride = '',
    String clientIdOverride = '',
    String apiBase = testRelay,
  }) {
    adapter = RouteAdapter({_docPath: answer ?? FakeAnswer(200, _doc())});
    return MuxbusAuthConfigSource(
      dio: Dio()..httpClientAdapter = adapter,
      apiBase: apiBase,
      domainOverride: domainOverride,
      clientIdOverride: clientIdOverride,
    );
  }

  group('normaliseCognitoDomain', () {
    test('a full https URL becomes its host', () {
      expect(
        normaliseCognitoDomain('https://auth.example.test'),
        'auth.example.test',
      );
      expect(
        normaliseCognitoDomain('https://auth.example.test/'),
        'auth.example.test',
      );
      expect(
        normaliseCognitoDomain('  https://auth.example.test/oauth2  '),
        'auth.example.test',
      );
    });

    test('a bare host stays a host, and a port is kept', () {
      expect(normaliseCognitoDomain('auth.example.test'), 'auth.example.test');
      expect(
        normaliseCognitoDomain('https://auth.example.test:8443'),
        'auth.example.test:8443',
      );
    });

    test('empty or not https is refused', () {
      expect(normaliseCognitoDomain(null), isNull);
      expect(normaliseCognitoDomain(''), isNull);
      expect(normaliseCognitoDomain('   '), isNull);
      expect(normaliseCognitoDomain('http://auth.example.test'), isNull);
    });
  });

  test(
    'reads the domain and the mobile client id from the discovery document',
    () async {
      final source = make();
      final config = await source.resolve();
      expect(config.domain, testAuthDomain);
      expect(config.clientId, testClientId);
      expect(adapter.requests.single.uri.toString(), '$testRelay$_docPath');
    },
  );

  test('a trailing slash on the relay base is tolerated', () async {
    final source = make(apiBase: '$testRelay/');
    await source.resolve();
    expect(adapter.requests.single.uri.toString(), '$testRelay$_docPath');
  });

  test('the document is read once per session', () async {
    final source = make();
    await source.resolve();
    await source.resolve();
    expect(await source.available(), isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('overrides win, and with both set nothing is fetched', () async {
    final source = make(
      domainOverride: 'https://override.example.test',
      clientIdOverride: 'override-client',
    );
    final config = await source.resolve();
    expect(config.domain, 'override.example.test');
    expect(config.clientId, 'override-client');
    expect(adapter.requests, isEmpty);
  });

  test(
    'each override wins on its own; the rest comes from the document',
    () async {
      final byClient =
          await make(clientIdOverride: 'override-client').resolve();
      expect(byClient.domain, testAuthDomain);
      expect(byClient.clientId, 'override-client');

      final byDomain =
          await make(domainOverride: 'override.example.test').resolve();
      expect(byDomain.domain, 'override.example.test');
      expect(byDomain.clientId, testClientId);
    },
  );

  test('no mobile client id anywhere: sign-in is not available', () async {
    final source = make(answer: FakeAnswer(200, _doc(mobileClientId: null)));
    await expectLater(source.resolve(), throwsA(isA<AuthUnavailable>()));
    expect(await source.available(), isFalse);
  });

  test(
    'the desktop client id is never used in place of the mobile one',
    () async {
      final source = make(answer: FakeAnswer(200, _doc(mobileClientId: '')));
      await expectLater(source.resolve(), throwsA(isA<AuthUnavailable>()));
    },
  );

  test('a relay without the document (404): not available', () async {
    final source = make(answer: const FakeAnswer(404));
    await expectLater(source.resolve(), throwsA(isA<AuthUnavailable>()));
  });

  test('a domain that is not https counts as missing', () async {
    final source = make(
      answer: FakeAnswer(200, _doc(domain: 'http://auth.example.test')),
    );
    await expectLater(source.resolve(), throwsA(isA<AuthUnavailable>()));
  });

  test(
    'offline: a network error, unknown availability, and asked again later',
    () async {
      final source = make(answer: const FakeAnswer.offline());
      await expectLater(source.resolve(), throwsA(isA<AuthNetworkError>()));
      expect(await source.available(), isNull);
      adapter.routes[_docPath] = FakeAnswer(200, _doc());
      final config = await source.resolve();
      expect(config.clientId, testClientId);
    },
  );
}
