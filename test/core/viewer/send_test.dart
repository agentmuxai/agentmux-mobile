import 'dart:convert';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/viewer/send_signature.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewer_fakes.dart';

ViewerClient _client(FakeAdapter adapter) => ViewerClient(
      host: '198.51.100.20',
      port: 29800,
      fingerprint: testFingerprint,
      token: 'amxv_t',
      adapter: adapter,
    );

/// "Signs" by returning the text it was given, so the test sees it.
Future<Uint8List> _echo(Uint8List text) async => text;

void main() {
  test('the signed text is five lines, the body hash last', () {
    // The same vector the computer's own check is tested with.
    expect(
      utf8.decode(signedString(
        method: 'POST',
        path: '/agentmux/viewer/agents/A%20B/input',
        timestampMs: 42,
        body: const [],
      )),
      'amxv-sig-v1\nPOST\n/agentmux/viewer/agents/A%20B/input\n42\n'
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  group('sendInput', () {
    test('posts the message, signed over the exact body, with the headers', () async {
      final adapter = FakeAdapter([
        const FakeResponse(202, json: {'message_id': 'm-1', 'state': 'delivered'}),
      ]);
      final at = DateTime.fromMillisecondsSinceEpoch(1791963024123);
      final result = await withClock(
        Clock.fixed(at),
        () => _client(adapter).sendInput(
          'Agent A',
          message: 'Run the tests again — "now"',
          messageId: 'm-1',
          sign: _echo,
        ),
      );
      expect(result, isA<SendAccepted>());
      expect((result as SendAccepted).queued, isFalse);
      expect(result.duplicate, isFalse);

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/agentmux/viewer/agents/Agent%20A/input');
      expect(req.headers['Authorization'], 'Bearer amxv_t');
      expect(req.headers['X-Amxv-Timestamp'], '1791963024123');
      expect(req.headers['Content-Type'], startsWith('application/json'));
      // The body goes out as the string that was hashed, not re-encoded.
      final body = adapter.bodies.single as String;
      expect(jsonDecode(body), {'message': 'Run the tests again — "now"', 'message_id': 'm-1'});
      // The "signature" is the text, so it can be read back.
      final signed = utf8.decode(base64.decode(req.headers['X-Amxv-Signature'] as String));
      final lines = signed.split('\n');
      expect(lines, hasLength(5));
      expect(lines.sublist(0, 4), ['amxv-sig-v1', 'POST', '/agentmux/viewer/agents/Agent%20A/input', '1791963024123']);
      // The last line is the hash of the body that was sent.
      expect(lines[4], sha256.convert(utf8.encode(body)).toString());
    });

    test('202 queued and duplicate', () async {
      final adapter = FakeAdapter([
        const FakeResponse(202, json: {'message_id': 'm-1', 'state': 'queued'}),
        const FakeResponse(202, json: {'message_id': 'm-1', 'state': 'delivered', 'duplicate': true}),
      ]);
      final client = _client(adapter);
      final first = await client.sendInput('A', message: 'x', messageId: 'm-1', sign: _echo) as SendAccepted;
      expect(first.queued, isTrue);
      final second = await client.sendInput('A', message: 'x', messageId: 'm-1', sign: _echo) as SendAccepted;
      expect(second.duplicate, isTrue);
    });

    test('each refusal is a kind, with what the computer said', () async {
      final cases = <(int, Map<String, Object?>, SendRefusal)>[
        (400, {'error': 'bad'}, SendRefusal.badRequest),
        (403, {'error': 'off', 'reason': 'send_off'}, SendRefusal.sendOff),
        (403, {'error': 'k', 'reason': 'pair_again'}, SendRefusal.pairAgain),
        (403, {'error': 's', 'reason': 'bad_signature'}, SendRefusal.badSignature),
        (403, {'error': 't', 'reason': 'stale_timestamp'}, SendRefusal.staleTimestamp),
        (403, {'error': 'x', 'reason': 'something_new'}, SendRefusal.other),
        (404, {'error': 'none'}, SendRefusal.noSuchAgent),
        (409, {'error': 'n', 'reason': 'not_running'}, SendRefusal.notRunning),
        (409, {'error': 'n', 'reason': 'starting'}, SendRefusal.starting),
        (409, {'error': 'n', 'reason': 'needs_login'}, SendRefusal.needsLogin),
        (409, {'error': 'n', 'reason': 'in_flight'}, SendRefusal.inFlight),
        (409, {'error': 'n', 'reason': 'not_supported'}, SendRefusal.notSupported),
        (409, {'error': 'boom', 'reason': 'failed'}, SendRefusal.failed),
        (413, {'error': 'long'}, SendRefusal.tooLong),
        (429, {'error': 'slow'}, SendRefusal.rateLimited),
        (500, {'error': 'oops'}, SendRefusal.other),
      ];
      for (final (status, body, kind) in cases) {
        final adapter = FakeAdapter([FakeResponse(status, json: body)]);
        final result = await _client(adapter).sendInput('A', message: 'x', messageId: 'm', sign: _echo);
        expect(result, isA<SendRefused>(), reason: '$status $body');
        final refused = result as SendRefused;
        expect(refused.kind, kind, reason: '$status $body');
        expect(refused.status, status);
        expect(refused.error, body['error']);
      }
    });

    test('401 is ViewerUnauthorized', () async {
      final adapter = FakeAdapter([const FakeResponse(401, json: {'error': 'no'})]);
      await expectLater(
        _client(adapter).sendInput('A', message: 'x', messageId: 'm', sign: _echo),
        throwsA(isA<ViewerUnauthorized>()),
      );
    });
  });

  group('hello.send', () {
    Future<SendGrant> grantOf(Map<String, Object?> extra) async {
      final adapter = FakeAdapter([
        FakeResponse(200, json: {'hostname': 'h', 'device_id': 'd', ...extra}),
      ]);
      return (await _client(adapter).hello()).send;
    }

    test('allowed, off and pair_again', () async {
      expect(await grantOf({'send': 'allowed'}), SendGrant.allowed);
      expect(await grantOf({'send': 'off'}), SendGrant.off);
      expect(await grantOf({'send': 'pair_again'}), SendGrant.pairAgain);
    });

    test('no send at all is a computer from before sending; an unknown word is not allowed', () async {
      expect(await grantOf({}), SendGrant.tooOld);
      expect(await grantOf({'send': 'maybe'}), SendGrant.off);
    });
  });

  group('pair with a key', () {
    const grant = {'token': 'amxv_dGVzdA', 'device_id': 'dev-9'};

    test('sends device_key when there is one', () async {
      final adapter = FakeAdapter([const FakeResponse(200, json: grant)]);
      await _client(adapter).pair(code: 'ABCDEFGH23', deviceName: 'd', deviceKey: 'a2V5');
      expect((adapter.bodies.single as Map)['device_key'], 'a2V5');
    });

    test('a 400 about device_key is deviceKeyRefused; any other 400 is not', () async {
      final refused = FakeAdapter([
        const FakeResponse(400, json: {'error': 'device_key must be standard base64 of a 32-byte public key'}),
      ]);
      await expectLater(
        _client(refused).pair(code: 'ABCDEFGH23', deviceName: 'd', deviceKey: 'a2V5'),
        throwsA(isA<PairingException>().having((e) => e.failure, 'failure', PairingFailure.deviceKeyRefused)),
      );
      final other = FakeAdapter([const FakeResponse(400, json: {'error': 'bad code format'})]);
      await expectLater(
        _client(other).pair(code: 'ABCDEFGH23', deviceName: 'd', deviceKey: 'a2V5'),
        throwsA(isA<PairingException>().having((e) => e.failure, 'failure', PairingFailure.unreachable)),
      );
      // With no key sent, device_key is not the problem.
      final none = FakeAdapter([
        const FakeResponse(400, json: {'error': 'device_key must be standard base64 of a 32-byte public key'}),
      ]);
      await expectLater(
        _client(none).pair(code: 'ABCDEFGH23', deviceName: 'd'),
        throwsA(isA<PairingException>().having((e) => e.failure, 'failure', PairingFailure.unreachable)),
      );
    });
  });
}
