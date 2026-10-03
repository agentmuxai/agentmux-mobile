import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/fleet/fleet_snapshot.dart';
import 'package:agentmux_mobile/core/fleet/sse.dart';

void main() {
  group('SseParser', () {
    test('dispatches an event with its type, data and id', () {
      final p = SseParser();
      final events = p.add('retry: 3000\n\nevent: fleet\nid: e1:2\ndata: {"a":1}\n\n');
      expect(events, hasLength(1));
      expect(events.single.event, 'fleet');
      expect(events.single.id, 'e1:2');
      expect(events.single.data, '{"a":1}');
      expect(p.retryMs, 3000);
      expect(p.lastEventId, 'e1:2');
    });

    test('comments (heartbeats) dispatch nothing', () {
      expect(SseParser().add(': hb\n\n: hb\n\n'), isEmpty);
    });

    test('joins multi-line data and defaults the type to message', () {
      final e = SseParser().add('data: one\ndata: two\n\n').single;
      expect(e.event, 'message');
      expect(e.data, 'one\ntwo');
    });

    test('an event split across chunks dispatches once it is complete', () {
      final p = SseParser();
      expect(p.add('event: fl'), isEmpty);
      expect(p.add('eet\ndata: {"x"'), isEmpty);
      expect(p.add(':2}\n'), isEmpty);
      final events = p.add('\n');
      expect(events.single.event, 'fleet');
      expect(events.single.data, '{"x":2}');
    });

    test('handles CRLF, including a CR and LF split across two chunks', () {
      final p = SseParser();
      expect(p.add('data: a\r'), isEmpty);
      expect(p.add('\n\r\n').single.data, 'a');
      // A trailing CR waits for the next chunk (it may be half of CRLF), so
      // something must follow the last one for it to count.
      expect(
          SseParser().add('data: b\r\rdata: c\r\r: next').map((e) => e.data),
          ['b', 'c']);
    });

    test('only one leading space is stripped from a value', () {
      expect(SseParser().add('data:  two spaces\n\n').single.data,
          ' two spaces');
    });

    test('an id containing NUL is ignored', () {
      final p = SseParser()..add('id: a\u0000b\ndata: x\n\n');
      expect(p.lastEventId, isNull);
    });

    test('refuses an unterminated line past the size limit', () {
      final p = SseParser();
      expect(() => p.add('data: ${'x' * (SseParser.maxLineLength + 1)}'),
          throwsFormatException);
    });
  });

  group('FleetSnapshot.tryParse', () {
    test('parses the spec 4.1 body', () {
      final s = FleetSnapshot.tryParse({
        'epoch': '9f2c41d07a6b3e58',
        'rev': 12,
        'hostname': 'narko',
        'channel': 'local-main-b28b7a-051fbf53',
        'version': '0.59.7',
        'agents': ['AgentY', 'Clamk'],
      })!;
      expect(s.eventId, '9f2c41d07a6b3e58:12');
      expect(s.hostname, 'narko');
      expect(s.channel, 'local-main-b28b7a-051fbf53');
      expect(s.agents, ['AgentY', 'Clamk']);
    });

    test('rejects a body that is not a fleet snapshot', () {
      expect(FleetSnapshot.tryParse(null), isNull);
      expect(FleetSnapshot.tryParse({'agents': []}), isNull);
      expect(FleetSnapshot.tryParse({'epoch': 'e', 'rev': '1', 'agents': []}),
          isNull);
    });

    test('bounds what an unauthenticated peer can send', () {
      final s = FleetSnapshot.tryParse({
        'epoch': 'e',
        'rev': 1,
        'channel': '',
        'agents': [
          'ok',
          '',
          42,
          'x' * (FleetSnapshot.maxNameLength + 1),
          ...List.generate(FleetSnapshot.maxAgents + 10, (i) => 'a$i'),
        ],
      })!;
      expect(s.channel, isNull);
      expect(s.agents.first, 'ok');
      expect(s.agents, hasLength(FleetSnapshot.maxAgents));
      expect(s.agents.every((a) => a.length <= FleetSnapshot.maxNameLength),
          isTrue);
    });
  });
}
