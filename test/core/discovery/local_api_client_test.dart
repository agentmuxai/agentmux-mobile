import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/local_api_client.dart';

DioException _dioWithStatus(int status) {
  final req = RequestOptions(path: '/agentmux/discovery');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('LocalApiClient.fetchAgentsFailureMessage', () {
    // fetchAgents() is only ever reached via _enrichWithAgents, whose sole
    // callers are the mDNS scanner and UDP broadcast prober — every instance
    // that reaches here carries the narrow lan_key, never the full instance
    // key, and /agentmux/discovery isn't among the routes that key grants.
    // An earlier version of this message wrongly said "rebuild the app"
    // (Codex P2 on agentmux-mobile#20/#21) — rebuilding cannot change what a
    // lan_key is scoped to. A later version stated the lan_key-scoping cause
    // as flat certainty, which ReAgent correctly flagged (twice) as unsound:
    // that fact lives entirely in a sibling repo this one can't verify
    // against, so a confidently wrong diagnosis here would read a REAL
    // stale/rotated key as "expected, not a bug" and stop it being
    // investigated. Hedged deliberately — see the source's own doc comment.
    // The rebuild-fixable staleness case is real, but belongs to dev
    // auto-connect specifically, covered separately in
    // discovery_provider_test.dart.
    test('a 401 offers the lan_key-scoping explanation, hedged', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        _dioWithStatus(401),
        'http://192.168.1.68:60371',
      );
      expect(msg, contains('401'));
      expect(msg, contains('lan_key'));
      expect(msg, contains('likely'), reason: 'must not overclaim certainty');
      // "stale" is allowed to appear as the ruled-in alternative explanation
      // ("...rather than a stale/rotated key") — what must NOT happen is the
      // message asserting staleness as the diagnosis, or telling anyone to
      // rebuild (that WAS the bug: Codex P2 on agentmux-mobile#20/#21).
      expect(msg, isNot(contains('Rebuild')));
      expect(msg, contains('http://192.168.1.68:60371'));
    });

    test('other Dio status codes keep the generic message', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        _dioWithStatus(500),
        'http://192.168.1.68:60371',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('lan_key')));
    });

    test('a non-Dio error keeps the generic message', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        StateError('boom'),
        'http://192.168.1.68:60371',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('lan_key')));
      expect(msg, contains('http://192.168.1.68:60371'));
    });

    // A connect timeout has no response at all — `response?.statusCode` is
    // null, which must not be mistaken for a 401.
    test('a Dio error with no response keeps the generic message', () {
      final req = RequestOptions(path: '/agentmux/discovery');
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        DioException(
          requestOptions: req,
          type: DioExceptionType.connectionTimeout,
        ),
        'http://10.0.2.2:60237',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('lan_key')));
    });
  });

  group('LocalApiClient discovery parsing', () {
    test('parseDiscovery reads this instance and tags sibling-channel agents',
        () {
      final info = LocalApiClient.parseDiscovery({
        'host': {
          'hostname': 'narko',
          'version': '0.59.7',
          'addressable': [
            {'agent_id': 'Clamk', 'last_seen': 5},
          ],
          'cross_channel': [
            {'name': 'Korp', 'channel': 'dev', 'local_url': 'http://127.0.0.1:29706'},
            {'name': 'AgentY', 'channel': 'stable', 'local_url': 'http://127.0.0.1:29700'},
          ],
        },
      });
      expect(info.hostname, 'narko');
      expect(info.version, '0.59.7');
      expect(info.agents.map((a) => a.name), ['Clamk', 'Korp', 'AgentY']);
      expect(info.agents.map((a) => a.channel), [null, 'dev', 'stable']);
    });

    test('parseDiscovery tolerates a server with no cross_channel', () {
      final info = LocalApiClient.parseDiscovery({
        'host': {
          'addressable': [
            {'agent_id': 'Clamk'},
          ],
        },
      });
      expect(info.agents.map((a) => a.name), ['Clamk']);
    });

    test('parseAgentNames reads the lan_key agent-names body', () {
      final agents = LocalApiClient.parseAgentNames({
        'agents': ['Clare', 'AgentO'],
      });
      expect(agents.map((a) => a.name), ['Clare', 'AgentO']);
      expect(agents.every((a) => a.channel == null), isTrue);
    });

    test('parseAgentNames returns nothing for a missing or malformed body', () {
      expect(LocalApiClient.parseAgentNames(null), isEmpty);
      expect(LocalApiClient.parseAgentNames({'agents': 'nope'}), isEmpty);
    });
  });

  group('LocalApiClient.isDiscoveryRouteRefused', () {
    // The desktop refuses /agentmux/discovery to a lan_key holder; the
    // agent-names fallback is only right for that refusal.
    test('401, 403 and 404 trigger the agent-names fallback', () {
      for (final status in [401, 403, 404]) {
        expect(LocalApiClient.isDiscoveryRouteRefused(_dioWithStatus(status)), isTrue);
      }
    });

    test('a server error or a timeout does not', () {
      expect(LocalApiClient.isDiscoveryRouteRefused(_dioWithStatus(500)), isFalse);
      final req = RequestOptions(path: '/agentmux/discovery');
      expect(
        LocalApiClient.isDiscoveryRouteRefused(DioException(
          requestOptions: req,
          type: DioExceptionType.connectionTimeout,
        )),
        isFalse,
      );
    });
  });
}
