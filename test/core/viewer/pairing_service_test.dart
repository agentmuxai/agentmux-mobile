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
      );

  setUp(() {
    stored = [];
    pins = [];
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
    // No device key until phase 5.
    final body = adapter.bodies.single as Map;
    expect(body.containsKey('device_key'), isFalse);
    expect(body['device_name'], 'test device');
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
