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
      expect(parseInstallId('testinstallidtestinstallid'),
          'testinstallidtestinstallid');
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

  group('agent states', () {
    test('each known state parses; anything else is no state', () {
      expect(parseAgentState('working'), AgentState.working);
      expect(parseAgentState('waiting'), AgentState.waiting);
      expect(parseAgentState('idle'), AgentState.idle);
      expect(parseAgentState('stopped'), AgentState.stopped);
      expect(parseAgentState('error'), AgentState.error);
      for (final bad in <Object?>[
        null,
        '',
        'Working',
        'busy',
        'running',
        ' idle',
        1,
        ['idle'],
      ]) {
        expect(parseAgentState(bad), isNull, reason: '$bad');
      }
    });

    test('a Unix time is a positive integer', () {
      expect(parseUnixMs(1791352494000), 1791352494000);
      expect(parseUnixMs(0), isNull);
      expect(parseUnixMs(-5), isNull);
      expect(parseUnixMs(1791352494000.5), isNull);
      expect(parseUnixMs('1791352494000'), isNull);
      expect(parseUnixMs(null), isNull);
    });

    test('agent_status is keyed by lower-cased name', () {
      final status = parseAgentStatus({
        'AgentX': {'state': 'working', 'since_ms': 1000},
        'Camper': {'state': 'idle'},
      });
      expect(status, {
        'agentx': const ReportedAgentStatus(AgentState.working, sinceMs: 1000),
        'camper': const ReportedAgentStatus(AgentState.idle),
      });
    });

    test('a bad state drops the entry; a bad since_ms drops only the time',
        () {
      final status = parseAgentStatus({
        'Unknown': {'state': 'thinking', 'since_ms': 1000},
        'NoState': {'since_ms': 1000},
        'NotAMap': 'working',
        '': {'state': 'idle'},
        'n' * 129: {'state': 'idle'},
        'BadSince': {'state': 'waiting', 'since_ms': -1},
        'TextSince': {'state': 'error', 'since_ms': '1000'},
      });
      expect(status, {
        'badsince': const ReportedAgentStatus(AgentState.waiting),
        'textsince': const ReportedAgentStatus(AgentState.error),
      });
    });

    test('agent_status that is not a map is empty, and is bounded', () {
      expect(parseAgentStatus(null), isEmpty);
      expect(
        parseAgentStatus([
          {'state': 'idle'},
        ]),
        isEmpty,
      );
      final many = {
        for (var i = 0; i < 50; i++) 'a$i': {'state': 'idle'},
      };
      expect(parseAgentStatus(many, maxEntries: 10), hasLength(10));
    });
  });

  group('time in a state', () {
    final receivedAt = DateTime(2026, 10, 7, 12);

    test("comes from the desktop's own two times, never the device clock", () {
      // The desktop's clock is a year ahead of this device's: only the
      // difference between its own two times counts.
      const desktopNow = 1823000000000;
      final since = stateSinceFrom(
        sinceMs: desktopNow - 3 * 60 * 1000,
        nowMs: desktopNow,
        receivedAt: receivedAt,
      )!;
      expect(since.elapsedAtReceipt, const Duration(minutes: 3));
      expect(since.elapsed(receivedAt), const Duration(minutes: 3));
      expect(
        since.elapsed(receivedAt.add(const Duration(minutes: 2))),
        const Duration(minutes: 5),
      );
    });

    test('is unknown without now_ms or since_ms', () {
      expect(
        stateSinceFrom(sinceMs: 1000, nowMs: null, receivedAt: receivedAt),
        isNull,
      );
      expect(
        stateSinceFrom(sinceMs: null, nowMs: 1000, receivedAt: receivedAt),
        isNull,
      );
    });

    test('a since_ms after now_ms counts as just now', () {
      final since =
          stateSinceFrom(sinceMs: 5000, nowMs: 1000, receivedAt: receivedAt)!;
      expect(since.elapsedAtReceipt, Duration.zero);
    });

    test('a device clock that steps back never shrinks it', () {
      final since = StateSince(
        elapsedAtReceipt: const Duration(minutes: 3),
        receivedAt: receivedAt,
      );
      expect(
        since.elapsed(receivedAt.subtract(const Duration(hours: 1))),
        const Duration(minutes: 3),
      );
    });

    test('lanAgentFrom applies kind, state and time', () {
      final a = lanAgentFrom(
        'AgentX',
        kind: AgentKind.container,
        status: const ReportedAgentStatus(AgentState.working, sinceMs: 1000),
        nowMs: 61000,
        receivedAt: receivedAt,
      );
      expect(a.kind, AgentKind.container);
      expect(a.state, AgentState.working);
      expect(a.stateSince!.elapsedAtReceipt, const Duration(minutes: 1));
      expect(a.stateAsOf, isNull);
      final none = lanAgentFrom('Old', receivedAt: receivedAt);
      expect(none.state, isNull);
      expect(none.stateSince, isNull);
    });
  });
}
