import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/local_api_client.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';

DioException _dioWithStatus(int status) {
  final req = RequestOptions(path: '/agentmux/discovery');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

void main() {
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

    test('parseAgentNames reads agent_kinds when the desktop sends them', () {
      final agents = LocalApiClient.parseAgentNames({
        'agents': ['AgentX', 'Camper', 'Old'],
        'agent_kinds': {'agentx': 'container', 'Camper': 'host', 'Old': 'vm'},
      });
      expect(agents.map((a) => a.kind),
          [AgentKind.container, AgentKind.host, null]);
    });

    test('parseAgentNames without agent_kinds gives no kinds', () {
      final agents = LocalApiClient.parseAgentNames({
        'agents': ['AgentX'],
      });
      expect(agents.single.kind, isNull);
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

  group('LocalApiClient agent-names status', () {
    final receivedAt = DateTime(2026, 10, 7, 12);

    test('parseAgentNames reads agent_status and now_ms', () {
      final agents = LocalApiClient.parseAgentNames({
        'agents': ['AgentX', 'Camper', 'Shell'],
        'now_ms': 1791352494000,
        'agent_status': {
          'agentx': {'state': 'working', 'since_ms': 1791352374000},
          'Camper': {'state': 'idle', 'since_ms': 1791352000000},
        },
      }, receivedAt: receivedAt);
      expect(agents.map((a) => a.state),
          [AgentState.working, AgentState.idle, null]);
      expect(
        agents.first.stateSince,
        StateSince(
          elapsedAtReceipt: const Duration(minutes: 2),
          receivedAt: receivedAt,
        ),
      );
      // An agent left out of the map has no state: no chip, not "idle".
      expect(agents.last.stateSince, isNull);
    });

    test('without now_ms a state has no time', () {
      final agents = LocalApiClient.parseAgentNames({
        'agents': ['AgentX'],
        'agent_status': {
          'AgentX': {'state': 'working', 'since_ms': 1791352374000},
        },
      }, receivedAt: receivedAt);
      expect(agents.single.state, AgentState.working);
      expect(agents.single.stateSince, isNull);
    });

    test('an older desktop body gives no states', () {
      final agents = LocalApiClient.parseAgentNames({
        'agents': ['AgentX'],
      });
      expect(agents.single.state, isNull);
      expect(agents.single.stateSince, isNull);
    });
  });
}
