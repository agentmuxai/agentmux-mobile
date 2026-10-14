import 'dart:convert';

import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/pairing_service.dart';
import 'package:agentmux_mobile/core/viewer/scanned_code.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewer_fakes.dart';

const _code = PairCode(
  host: '198.51.100.20',
  port: 29800,
  fingerprint: testFingerprint,
  code: 'ABCDEFGH23',
  hostname: 'host-a',
  channel: 'stable',
);

void main() {
  late FakeAdapter adapter;
  late List<PairedHost> stored;
  late List<String?> pins;
  late FakeDeviceKeyStore keys;

  PairingService service() => PairingService(
        clientFor: ({required host, required port, required fingerprint, token}) {
          pins.add(fingerprint);
          return ViewerClient(
            host: host,
            port: port,
            fingerprint: fingerprint,
            token: token,
            adapter: adapter,
          );
        },
        store: (h) async => stored.add(h),
        keys: keys,
      );

  setUp(() {
    stored = [];
    pins = [];
    keys = FakeDeviceKeyStore();
  });

  test('200: the grant is stored with the pinned fingerprint', () async {
    adapter = FakeAdapter([
      const FakeResponse(200, json: {
        'token': 'amxv_dGVzdA',
        'device_id': 'dev-9',
        'hostname': 'host-a',
        'channel': 'stable',
        'version': '0.60.0',
        'install_id': testInstallId,
      }),
    ]);
    final host = await service().pair(_code, deviceName: 'test device');
    expect(stored.single, same(host));
    expect(host.token, 'amxv_dGVzdA');
    expect(host.fingerprint, testFingerprint);
    expect(host.host, '198.51.100.20');
    expect(host.port, 29800);
    expect(host.hostname, 'host-a');
    expect(host.channel, 'stable');
    expect(host.installId, testInstallId);
    expect(host.deviceId, 'dev-9');
    expect(host.invalid, isFalse);
    // The connection was pinned to the QR code's fingerprint.
    expect(pins, [testFingerprint]);
    // The public half of the key made for this pairing went with the code.
    final body = adapter.bodies.single as Map;
    expect(keys.keys.keys, ['amxv-${host.id}']);
    expect(body['device_key'], base64.encode(keys.keys['amxv-${host.id}']!));
    expect(body['device_name'], 'test device');
  });

  test('no key store: pairs without a key, for watching', () async {
    adapter = FakeAdapter([const FakeResponse(200, json: {'token': 'amxv_dGVzdA', 'device_id': 'dev-9'})]);
    keys.failCreate = true;
    final host = await service().pair(_code);
    expect(stored.single, same(host));
    expect((adapter.bodies.single as Map).containsKey('device_key'), isFalse);
  });

  test('a computer that takes only a 32-byte key: the same code again without one', () async {
    adapter = FakeAdapter([
      const FakeResponse(400, json: {'error': 'device_key must be standard base64 of a 32-byte public key'}),
      const FakeResponse(200, json: {'token': 'amxv_dGVzdA', 'device_id': 'dev-9'}),
    ]);
    final host = await service().pair(_code);
    expect(adapter.bodies, hasLength(2));
    expect((adapter.bodies[0] as Map).containsKey('device_key'), isTrue);
    expect((adapter.bodies[1] as Map).containsKey('device_key'), isFalse);
    expect((adapter.bodies[1] as Map)['code'], 'ABCDEFGH23', reason: 'the same code');
    expect(stored.single, same(host));
    expect(keys.keys, isEmpty, reason: 'the key is not kept');
    expect(keys.deleted, ['amxv-${host.id}']);
  });

  test('a pairing that fails leaves no key behind', () async {
    adapter = FakeAdapter([const FakeResponse(401, json: {})]);
    await expectLater(service().pair(_code), throwsA(isA<PairingException>()));
    expect(keys.keys, isEmpty);
    expect(keys.deleted, hasLength(1));
    expect(stored, isEmpty);
  });

  test('401: nothing is stored', () async {
    adapter = FakeAdapter([const FakeResponse(401, json: {})]);
    await expectLater(
      service().pair(_code),
      throwsA(isA<PairingException>().having(
          (e) => e.failure, 'failure', PairingFailure.codeRejected)),
    );
    expect(stored, isEmpty);
  });

  test('429: nothing is stored', () async {
    adapter = FakeAdapter([const FakeResponse(429, json: {})]);
    await expectLater(
      service().pair(_code),
      throwsA(isA<PairingException>().having(
          (e) => e.failure, 'failure', PairingFailure.rateLimited)),
    );
    expect(stored, isEmpty);
  });

  test('the QR code names the host when the response does not', () async {
    adapter = FakeAdapter([
      const FakeResponse(200, json: {'token': 'amxv_x', 'device_id': 'd'}),
    ]);
    final host = await service().pair(_code);
    expect(host.hostname, 'host-a');
    expect(host.channel, 'stable');
    expect(host.installId, isNull);
  });
}
