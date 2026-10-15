import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/logging/app_logger.dart';
import 'package:agentmux_mobile/core/viewer/device_key_store.dart';
import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/feed/send_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/viewer/viewer_fakes.dart';

/// An adapter that never reaches the computer.
class _Unreachable implements HttpClientAdapter {
  var calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    calls++;
    throw DioException.connectionError(requestOptions: options, reason: 'down');
  }

  @override
  void close({bool force = false}) {}
}

const _accepted = FakeResponse(202, json: {'message_id': 'x', 'state': 'delivered'});

void main() {
  late FakeAdapter adapter;
  late FakeDeviceKeyStore keys;
  late SendController send;
  var unauthorized = 0;
  final pairing = PairingMatch(paired: testPairedHost(), host: '198.51.100.20', port: 29800);

  SendController controller(HttpClientAdapter a, {Duration takenFor = const Duration(seconds: 30)}) => SendController(
        clientFor: ({required host, required port, required fingerprint, token}) =>
            ViewerClient(host: host, port: port, fingerprint: fingerprint, token: token, adapter: a),
        pairing: pairing,
        agent: 'Agent A',
        keys: keys,
        onUnauthorized: () => unauthorized++,
        takenFor: takenFor,
        inFlightWait: const Duration(milliseconds: 5),
        random: Random(1),
      );

  Future<void> settle() => pumpEventQueue();

  setUp(() async {
    keys = FakeDeviceKeyStore();
    await keys.create(deviceKeyAlias('p1'));
    unauthorized = 0;
    adapter = FakeAdapter([_accepted]);
    send = controller(adapter);
  });

  tearDown(() => send.dispose());

  test('a message id is a version 4 uuid', () {
    final id = newMessageId(Random(3));
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(newMessageId(Random(4)), isNot(id));
  });

  group('the grant', () {
    test('is read from hello, and unknown until then', () async {
      adapter.hello = const FakeResponse(200, json: {'hostname': 'h', 'device_id': 'd', 'send': 'allowed'});
      expect(send.grant, isNull);
      await send.checkGrant();
      expect(send.grant, SendGrant.allowed);
    });

    test('an unreachable computer leaves it as it was; a 401 reports it', () async {
      final down = controller(_Unreachable());
      await down.checkGrant();
      expect(down.grant, isNull);
      down.dispose();

      adapter.hello = const FakeResponse(401, json: {});
      await send.checkGrant();
      expect(unauthorized, 1);
    });
  });

  group('sending', () {
    test('signs and posts the message, then waits for the feed to show it', () async {
      send.send('Run the tests again   \n');
      expect(send.messages.single.state, SentState.sending);
      await settle();
      final sent = send.messages.single;
      expect(sent.state, SentState.taken);

      final body = jsonDecode(adapter.bodies.single as String) as Map;
      expect(body['message'], 'Run the tests again', reason: 'trailing white space is trimmed');
      expect(body['message_id'], sent.id);
      final req = adapter.requests.single;
      expect(req.uri.path, '/agentmux/viewer/agents/Agent%20A/input');
      expect(req.headers['X-Amxv-Signature'], isNotNull);

      // Not the feed's yet: stays. Once the feed has it: gone.
      send.shown((id) => false);
      expect(send.messages, hasLength(1));
      send.shown((id) => id == sent.id);
      expect(send.messages, isEmpty);
    });

    test('empty and over-long messages are not sent', () async {
      expect(send.send('   \n'), isFalse);
      expect(send.send('é' * (maxMessageBytes ~/ 2 + 1)), isFalse, reason: 'bytes, not characters');
      expect(send.send('é' * (maxMessageBytes ~/ 2)), isTrue);
      await settle();
      expect(adapter.requests, hasLength(1));
    });

    test('a message the computer took but the feed never shows is dropped after a while', () async {
      send.dispose();
      send = controller(adapter, takenFor: const Duration(milliseconds: 30));
      send.send('hello');
      await settle();
      expect(send.messages.single.state, SentState.taken);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(send.messages, isEmpty);
    });

    test('a refusal keeps the text, says why, and Try again reuses the id', () async {
      adapter = FakeAdapter([
        const FakeResponse(409, json: {'error': 'n', 'reason': 'not_running'}),
        _accepted,
      ]);
      send.dispose();
      send = controller(adapter);
      send.send('hello');
      await settle();
      final sent = send.messages.single;
      expect(sent.state, SentState.failed);
      expect(sent.failure, SendFailure.refused);
      expect(sent.refusal!.kind, SendRefusal.notRunning);
      expect(sendFailureText(sent), contains('Open it on the computer'));
      expect(sent.text, 'hello');

      final firstId = sent.id;
      send.retry(firstId);
      expect(send.messages.single.state, SentState.sending);
      await settle();
      expect(send.messages.single.state, SentState.taken);
      expect(send.messages.single.id, firstId);
      expect([for (final b in adapter.bodies) (jsonDecode(b as String) as Map)['message_id']], [firstId, firstId]);
    });

    test('Try again sends the same text as the first attempt, and the log follows it by id and length', () async {
      AppLogger.clear();
      adapter = FakeAdapter([
        const FakeResponse(409, json: {'error': 'n', 'reason': 'needs_login'}),
        _accepted,
      ]);
      send.dispose();
      send = controller(adapter);
      const text = 'Phone send test from the iOS Simulator';
      send.send(text);
      await settle();
      final id = send.messages.single.id;
      send.retry(id);
      await settle();
      final bodies = [for (final b in adapter.bodies) jsonDecode(b as String) as Map];
      expect([for (final b in bodies) b['message']], [text, text]);
      expect([for (final b in bodies) b['message_id']], [id, id]);
      final lines = [for (final e in AppLogger.entries.reversed) if (e.name == 'Send') e.message];
      expect(lines, [
        'send $id: 38 chars, 38 bytes',
        startsWith('refused ('),
        'retry $id: 38 chars, 38 bytes',
        'accepted $id: 38 chars, 38 bytes',
      ]);
      expect(lines.join(), isNot(contains('Simulator')), reason: 'the log never holds the text');
    });

    test('Try again only applies to a failed message; discard forgets one', () async {
      adapter = FakeAdapter([const FakeResponse(413, json: {'error': 'long'})]);
      send.dispose();
      send = controller(adapter);
      send.send('hello');
      await settle();
      send.discard(send.messages.single.id);
      expect(send.messages, isEmpty);
      send.send('again');
      send.retry(send.messages.single.id);
      expect(send.messages.single.state, SentState.sending, reason: 'still the first try');
      await settle();
    });

    test('a refusal about this device updates the grant', () async {
      adapter = FakeAdapter([const FakeResponse(403, json: {'error': 'off', 'reason': 'send_off'})]);
      send.dispose();
      send = controller(adapter);
      send.send('hello');
      await settle();
      expect(send.grant, SendGrant.off);
    });

    test('in_flight is asked again shortly, a few times', () async {
      adapter = FakeAdapter([
        const FakeResponse(409, json: {'error': 'n', 'reason': 'in_flight'}),
        const FakeResponse(409, json: {'error': 'n', 'reason': 'in_flight'}),
        _accepted,
      ]);
      send.dispose();
      send = controller(adapter);
      send.send('hello');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(send.messages.single.state, SentState.taken);
      expect(adapter.requests, hasLength(3));
    });

    test('in_flight forever gives up as a failure', () async {
      adapter = FakeAdapter([const FakeResponse(409, json: {'error': 'n', 'reason': 'in_flight'})]);
      send.dispose();
      send = controller(adapter);
      send.send('hello');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await settle();
      expect(adapter.requests, hasLength(1 + SendController.inFlightRetries));
      expect(send.messages.single.state, SentState.failed);
      expect(send.messages.single.refusal!.kind, SendRefusal.inFlight);
    });

    test('no answer, a gone key and a 401 each fail with their own reason', () async {
      final down = _Unreachable();
      send.dispose();
      send = controller(down);
      send.send('hello');
      await settle();
      expect(send.messages.single.failure, SendFailure.unreachable);
      expect(sendFailureText(send.messages.single), contains("can't reach"));

      keys.keys.clear();
      send.dispose();
      send = controller(adapter);
      send.send('hello');
      await settle();
      expect(send.messages.single.failure, SendFailure.key);

      await keys.create(deviceKeyAlias('p1'));
      adapter = FakeAdapter([const FakeResponse(401, json: {})]);
      send.dispose();
      send = controller(adapter);
      send.send('hello');
      await settle();
      expect(send.messages.single.failure, SendFailure.unpaired);
      expect(unauthorized, 1);
    });

    test('a message sent after dispose does nothing', () async {
      send.dispose();
      expect(send.send('hello'), isFalse);
      expect(adapter.requests, isEmpty);
    });
  });
}
