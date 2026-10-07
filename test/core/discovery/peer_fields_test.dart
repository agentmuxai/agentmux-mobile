import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/discovery/peer_fields.dart';

void main() {
  group('parseOs', () {
    test('accepts the desktop token shape', () {
      for (final os in ['windows', 'macos', 'linux', 'freebsd', 'a_b-1']) {
        expect(parseOs(os), os);
      }
    });

    test('rejects anything else, without throwing', () {
      for (final bad in <Object?>[
        null,
        '',
        'Windows',
        'mac os',
        'linux\n',
        'x' * 17,
        'win/32',
        42,
        ['linux'],
      ]) {
        expect(parseOs(bad), isNull, reason: '$bad');
      }
    });
  });

  group('parseInstallId', () {
    test('accepts a base32 id and rejects junk', () {
      expect(parseInstallId('mw3am46w5weex4a4fqrc3avnua'),
          'mw3am46w5weex4a4fqrc3avnua');
      expect(parseInstallId(''), isNull);
      expect(parseInstallId('a b'), isNull);
      expect(parseInstallId('x' * 65), isNull);
      expect(parseInstallId(7), isNull);
    });
  });

  group('parseChannelsRunning', () {
    test('clamps to 1..99', () {
      expect(parseChannelsRunning(3), 3);
      expect(parseChannelsRunning(0), 1);
      expect(parseChannelsRunning(-4), 1);
      expect(parseChannelsRunning(1000), 99);
      expect(parseChannelsRunning(2.0), 2);
    });

    test('null when absent or not a number', () {
      expect(parseChannelsRunning(null), isNull);
      expect(parseChannelsRunning('3'), isNull);
      expect(parseChannelsRunning(double.nan), isNull);
    });
  });

  group('agent kinds', () {
    test('host and container map; anything else is no kind', () {
      expect(parseAgentKind('host'), AgentKind.host);
      expect(parseAgentKind('container'), AgentKind.container);
      expect(parseAgentKind('vm'), isNull);
      expect(parseAgentKind('HOST'), isNull);
      expect(parseAgentKind(null), isNull);
    });

    test('agent_kinds is keyed by lower-cased name, unknown kinds left out',
        () {
      final kinds = parseAgentKinds({
        'AgentX': 'container',
        'Camper': 'host',
        'Odd': 'vm',
        '': 'host',
        'Num': 5,
      });
      expect(kinds, {'agentx': AgentKind.container, 'camper': AgentKind.host});
    });

    test('agent_kinds that is not a map is empty, and is bounded', () {
      expect(parseAgentKinds(['host']), isEmpty);
      expect(parseAgentKinds(null), isEmpty);
      final many = {for (var i = 0; i < 50; i++) 'a$i': 'host'};
      expect(parseAgentKinds(many, maxEntries: 10), hasLength(10));
    });
  });
}
