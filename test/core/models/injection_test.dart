import 'package:agentmux_mobile/core/models/injection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Injection.fromInjectResponse', () {
    // Pins the actual response shape of POST /reactive/inject
    // (agentmux-cloud/muxbus/server/src/index.ts) — a flat object, no
    // nested "injection" key, no echoed "message". DOC-001 (2026-08-03
    // documentation analyst): the client previously called
    // Injection.fromJson(res.data!['injection']), which always threw
    // because that key never existed, so every Inject call failed in the
    // app even though the server successfully created and delivered it.
    test('parses the real flat server response, not a nested "injection" key', () {
      final response = {
        'success': true,
        'injection_id': 'inj_abc123',
        'source_agent': 'mobile:cognito-sub-1',
        'target_agent': 'agent1',
        'priority': 'urgent',
        'created_at': '2026-08-03T12:00:00.000Z',
        'ttl_seconds': 86400,
      };

      final injection = Injection.fromInjectResponse(response, message: 'do the thing');

      expect(injection.id, 'inj_abc123');
      expect(injection.targetAgent, 'agent1');
      expect(injection.sourceAgent, 'mobile:cognito-sub-1');
      expect(injection.priority, 'urgent');
      expect(injection.createdAt, '2026-08-03T12:00:00.000Z');
      // The server never echoes the message; the caller supplies it.
      expect(injection.message, 'do the thing');
      // status has no server-side field in this response; falls back to
      // the model's default rather than throwing on a missing key.
      expect(injection.status, 'pending');
    });

    test('defaults source_agent and priority when the server omits them', () {
      final response = {
        'success': true,
        'injection_id': 'inj_xyz',
        'target_agent': 'agent2',
        'created_at': '2026-08-03T12:00:00.000Z',
      };

      final injection = Injection.fromInjectResponse(response, message: 'hi');

      expect(injection.sourceAgent, '');
      expect(injection.priority, 'normal');
    });

    test('a nested "injection" key (the old, wrong expected shape) is not required', () {
      // Regression guard: this must NOT throw a null-check/cast error the
      // way the pre-fix code did on every real server response.
      final response = {
        'success': true,
        'injection_id': 'inj_1',
        'target_agent': 'agent3',
        'created_at': '2026-08-03T12:00:00.000Z',
      };

      expect(
        () => Injection.fromInjectResponse(response, message: 'm'),
        returnsNormally,
      );
    });
  });
}
