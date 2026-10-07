import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/viewer/feed_events.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewer_fakes.dart';

ViewerClient _client(FakeAdapter adapter, {String? token}) => ViewerClient(
      host: '198.51.100.20',
      port: 29800,
      fingerprint: testFingerprint,
      token: token,
      adapter: adapter,
    );

const _paired = {
  'token': 'amxv_dGVzdHRva2VuZm9ydGVzdHM',
  'device_id': 'dev-1',
  'hostname': 'host-a',
  'channel': 'stable',
  'version': '0.60.0',
  'install_id': testInstallId,
};

void main() {
  group('pair', () {
    test('200: posts code and name over https, returns the grant',
        () async {
      final adapter = FakeAdapter([const FakeResponse(200, json: _paired)]);
      final result = await _client(adapter).pair(
        code: 'ABCDEFGH23',
        deviceName: 'AgentMux Mobile (Android)',
      );
      expect(result.token, _paired['token']);
      expect(result.deviceId, 'dev-1');
      expect(result.installId, testInstallId);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.toString(),
          'https://198.51.100.20:29800/agentmux/viewer/pair');
      // No token before pairing.
      expect(req.headers['Authorization'], isNull);
      expect(adapter.bodies.single, {
        'code': 'ABCDEFGH23',
        'device_name': 'AgentMux Mobile (Android)',
      });
    });

    test('401: the code was refused', () async {
      final adapter = FakeAdapter([const FakeResponse(401, json: {})]);
      await expectLater(
        _client(adapter).pair(code: 'ABCDEFGH23', deviceName: 'd'),
        throwsA(isA<PairingException>().having(
            (e) => e.failure, 'failure', PairingFailure.codeRejected)),
      );
    });

    test('429: too many attempts', () async {
      final adapter = FakeAdapter([const FakeResponse(429, json: {})]);
      await expectLater(
        _client(adapter).pair(code: 'ABCDEFGH23', deviceName: 'd'),
        throwsA(isA<PairingException>().having(
            (e) => e.failure, 'failure', PairingFailure.rateLimited)),
      );
    });

    test('a 200 that is not a grant is refused', () async {
      final adapter = FakeAdapter([
        const FakeResponse(200, json: {'token': 'has spaces', 'device_id': 'd'}),
      ]);
      await expectLater(
        _client(adapter).pair(code: 'ABCDEFGH23', deviceName: 'd'),
        throwsA(isA<PairingException>().having(
            (e) => e.failure, 'failure', PairingFailure.unreachable)),
      );
    });
  });

  test('hello and agents send the bearer token and parse', () async {
    final adapter = FakeAdapter([
      const FakeResponse(200, json: {
        'hostname': 'host-a',
        'channel': 'stable',
        'version': '0.60.0',
        'device_id': 'dev-1',
      }),
      const FakeResponse(200, json: {
        'now_ms': 1000,
        'agents': [
          {'name': 'AgentA', 'kind': 'host', 'state': 'working', 'since_ms': 10},
          {'name': 'AgentB'},
          {'name': ''},
          'junk',
        ],
      }),
    ]);
    final client = _client(adapter, token: 'amxv_t');
    final hello = await client.hello();
    expect(hello.hostname, 'host-a');
    expect(hello.deviceId, 'dev-1');
    final agents = await client.agents();
    expect(agents.nowMs, 1000);
    expect(agents.agents.map((a) => a.name), ['AgentA', 'AgentB']);
    expect(agents.agents.first.kind, AgentKind.host);
    expect(agents.agents.first.state, 'working');
    for (final r in adapter.requests) {
      expect(r.headers['Authorization'], 'Bearer amxv_t');
    }
  });

  test('a 401 on a viewer route is ViewerUnauthorized', () async {
    final adapter = FakeAdapter([const FakeResponse(401, json: {})]);
    await expectLater(
      _client(adapter, token: 'amxv_t').agents(),
      throwsA(isA<ViewerUnauthorized>()),
    );
  });

  group('feed', () {
    test('accepted, then snapshot, append, status; Last-Event-ID is sent',
        () async {
      final adapter = FakeAdapter([
        const FakeResponse(200, chunks: [
          ': hb\n\n',
          'event: snapshot\nid: 3:2\ndata: {"provider":"claude","gen":3,'
              '"from_line":0,"next_line":2,"lines":["{}","{}"]}\n\n',
          'event: append\nid: 3:3\ndata: {"gen":3,"line":2,"lines":["{}"]}\n\n',
          'event: status\ndata: {"state":"working","since_ms":5,"now_ms":9}\n\n',
          'event: reset\ndata: {"reason":"replaced"}\n\n',
          'event: unknown\ndata: {}\n\n',
        ]),
      ]);
      final items = await _client(adapter, token: 'amxv_t')
          .feed('Agent A', lastEventId: '3:1')
          .toList();
      expect(items.first, isNull);
      final events = items.whereType<FeedEvent>().toList();
      expect(events, hasLength(4));
      final snap = events[0] as FeedSnapshot;
      expect(snap.provider, 'claude');
      expect(snap.gen, '3');
      expect(snap.nextLine, 2);
      expect(snap.id, '3:2');
      expect((events[1] as FeedAppend).line, 2);
      expect((events[2] as FeedStatus).state, 'working');
      expect((events[3] as FeedReset).reason, 'replaced');

      final req = adapter.requests.single;
      expect(req.uri.path, '/agentmux/viewer/agents/Agent%20A/feed');
      expect(req.headers['Last-Event-ID'], '3:1');
      expect(req.headers['Authorization'], 'Bearer amxv_t');
    });

    test('401 is ViewerUnauthorized, 404 ViewerNotFound', () async {
      await expectLater(
        _client(FakeAdapter([const FakeResponse(401, chunks: [])]))
            .feed('A')
            .toList(),
        throwsA(isA<ViewerUnauthorized>()),
      );
      await expectLater(
        _client(FakeAdapter([const FakeResponse(404, chunks: [])]))
            .feed('A')
            .toList(),
        throwsA(isA<ViewerNotFound>()),
      );
    });
  });
}
