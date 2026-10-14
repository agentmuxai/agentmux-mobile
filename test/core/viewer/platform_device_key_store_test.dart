import 'package:agentmux_mobile/core/viewer/device_key_store.dart';
import 'package:agentmux_mobile/core/viewer/platform_device_key_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PlatformDeviceKeyStore.channelName);
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  final point = Uint8List.fromList([0x04, ...List.filled(64, 7)]);

  test('create, sign and delete go to the platform with the alias', () async {
    answer((call) async => switch (call.method) {
          'create' => point,
          'sign' => Uint8List.fromList([0x30, 0x06, 1, 2, 3]),
          _ => null,
        });
    final store = PlatformDeviceKeyStore();
    expect(await store.create('amxv-p1'), point);
    expect(await store.sign('amxv-p1', Uint8List.fromList([1, 2, 3])), [0x30, 0x06, 1, 2, 3]);
    await store.delete('amxv-p1');
    expect(calls.map((c) => c.method), ['create', 'sign', 'delete']);
    expect(calls.map((c) => (c.arguments as Map)['alias']), everyElement('amxv-p1'));
    expect((calls[1].arguments as Map)['data'], [1, 2, 3]);
  });

  test('a key that is not a 65-byte uncompressed point is refused', () async {
    for (final bad in [Uint8List(64), Uint8List.fromList([0x02, ...List.filled(64, 1)]), Uint8List(0)]) {
      answer((_) async => bad);
      await expectLater(PlatformDeviceKeyStore().create('a'), throwsA(isA<DeviceKeyException>()), reason: '${bad.length}');
    }
    answer((_) async => null);
    await expectLater(PlatformDeviceKeyStore().create('a'), throwsA(isA<DeviceKeyException>()));
  });

  test('an empty signature is refused', () async {
    answer((_) async => Uint8List(0));
    await expectLater(PlatformDeviceKeyStore().sign('a', Uint8List(1)), throwsA(isA<DeviceKeyException>()));
  });

  test('a platform error, or no platform side, is a DeviceKeyException', () async {
    answer((_) async => throw PlatformException(code: 'key_store', message: 'KeyStoreException'));
    await expectLater(
      PlatformDeviceKeyStore().sign('a', Uint8List(1)),
      throwsA(isA<DeviceKeyException>().having((e) => e.message, 'message', 'KeyStoreException')),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await expectLater(PlatformDeviceKeyStore().create('a'), throwsA(isA<DeviceKeyException>()));
  });
}
