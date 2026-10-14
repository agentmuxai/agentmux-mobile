import 'package:flutter/services.dart';

import 'device_key_store.dart';

/// The Android Keystore and the iOS Secure Enclave (or keychain), through the
/// app's own platform channel (`DeviceKeyChannel.kt`, and `DeviceKeys` in
/// `AppDelegate.swift`).
class PlatformDeviceKeyStore implements DeviceKeyStore {
  PlatformDeviceKeyStore([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.agentmux.agentmux_mobile/device_key';

  final MethodChannel _channel;

  @override
  Future<Uint8List> create(String alias) async {
    final key = await _call<Uint8List>('create', {'alias': alias});
    // The 65-byte uncompressed point: what the computer expects, and nothing
    // else is worth sending.
    if (key == null || key.length != 65 || key[0] != 0x04) {
      throw const DeviceKeyException('the key store made a key of the wrong shape');
    }
    return key;
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    final signature = await _call<Uint8List>('sign', {'alias': alias, 'data': data});
    if (signature == null || signature.isEmpty) {
      throw const DeviceKeyException('the key store made no signature');
    }
    return signature;
  }

  @override
  Future<void> delete(String alias) => _call<void>('delete', {'alias': alias});

  Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DeviceKeyException(e.message ?? e.code);
    } on MissingPluginException {
      throw const DeviceKeyException('no key store on this device');
    }
  }
}
