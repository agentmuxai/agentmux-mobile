import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// This device's key for one paired computer, made and kept by the platform's
/// key store (Android Keystore, iOS Secure Enclave or keychain): ECDSA on
/// P-256, never exportable. The computer holds the public half, from
/// pairing, and checks what the phone sends with it
/// (`SPEC_SEND_FROM_THE_PHONE_2026_10_13.md` 5.2.1). One key per pairing,
/// named by [alias]; unpairing deletes it.
abstract class DeviceKeyStore {
  /// Makes the key [alias] (replacing one that exists) and returns its public
  /// half as the 65-byte uncompressed point, `0x04 ‖ X ‖ Y`.
  Future<Uint8List> create(String alias);

  /// SHA-256 with ECDSA over [data], as a DER (ASN.1) signature. Throws
  /// [DeviceKeyException] when the key is gone.
  Future<Uint8List> sign(String alias, Uint8List data);

  /// Removes the key [alias]; no error when there is none.
  Future<void> delete(String alias);
}

/// The key store failed or has no such key.
class DeviceKeyException implements Exception {
  const DeviceKeyException(this.message);
  final String message;

  @override
  String toString() => 'DeviceKeyException($message)';
}

/// For a platform with no key store here (and until the platform channel is
/// wired in): pairing then goes ahead without a key, for watching only.
class NoDeviceKeyStore implements DeviceKeyStore {
  const NoDeviceKeyStore();

  @override
  Future<Uint8List> create(String alias) =>
      Future.error(const DeviceKeyException('no key store on this device'));

  @override
  Future<Uint8List> sign(String alias, Uint8List data) =>
      Future.error(const DeviceKeyException('no key store on this device'));

  @override
  Future<void> delete(String alias) async {}
}

/// The key store pairing and sending use; overridden in tests.
final deviceKeyStoreProvider =
    Provider<DeviceKeyStore>((_) => const NoDeviceKeyStore());

/// The key store's name for a pairing's key.
String deviceKeyAlias(String pairId) => 'amxv-$pairId';
