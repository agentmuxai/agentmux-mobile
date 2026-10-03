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
