import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/fleet_snapshot.dart';

Map<String, Object?> _body([Map<String, Object?> extra = const {}]) => {
      'epoch': '9f2c41d07a6b3e58',
      'rev': 12,
      'hostname': 'narko',
      'channel': 'local-main',
      'version': '0.59.11',
      'agents': ['AgentX', 'Camper'],
      ...extra,
    };

void main() {
  group('FleetSnapshot.tryParse display fields', () {
    test('reads os, install_id, channels_running and agent_kinds', () {
      final s = FleetSnapshot.tryParse(_body({
        'os': 'windows',
        'install_id': 'pqkksqckrolze5wvcs6rqeic4e',
        'channels_running': 3,
        'agent_kinds': {'AgentX': 'container', 'Camper': 'host'},
      }))!;
      expect(s.os, 'windows');
      expect(s.installId, 'pqkksqckrolze5wvcs6rqeic4e');
      expect(s.channelsRunning, 3);
      expect(s.agentKinds,
          {'agentx': AgentKind.container, 'camper': AgentKind.host});
    });

    test('an older desktop body parses as before', () {
      final s = FleetSnapshot.tryParse(_body())!;
      expect(s.agents, ['AgentX', 'Camper']);
      expect(s.os, isNull);
      expect(s.installId, isNull);
      expect(s.channelsRunning, isNull);
      expect(s.agentKinds, isEmpty);
    });

    test('malformed fields are dropped, never fatal', () {
      final s = FleetSnapshot.tryParse(_body({
        'os': 'WINDOWS',
        'install_id': 12,
        'channels_running': 'lots',
        'agent_kinds': ['AgentX'],
      }))!;
      expect(s.os, isNull);
      expect(s.installId, isNull);
      expect(s.channelsRunning, isNull);
      expect(s.agentKinds, isEmpty);
    });

    test('an unknown kind gives that agent no kind', () {
      final s = FleetSnapshot.tryParse(
          _body({'agent_kinds': {'AgentX': 'vm', 'Camper': 'host'}}))!;
      expect(s.agentKinds, {'camper': AgentKind.host});
    });

    test('oversized lists are cut', () {
      final names = [for (var i = 0; i < 900; i++) 'a$i'];
      final s = FleetSnapshot.tryParse(_body({
        'agents': names,
        'agent_kinds': {for (final n in names) n: 'host'},
      }))!;
      expect(s.agents, hasLength(FleetSnapshot.maxAgents));
      expect(s.agentKinds.length, lessThanOrEqualTo(FleetSnapshot.maxAgents));
    });
  });
}
