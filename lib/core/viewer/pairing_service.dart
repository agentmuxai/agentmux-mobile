import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import 'device_key_store.dart';
import 'paired_host.dart';
import 'paired_hosts_repository.dart';
import 'scanned_code.dart';
import 'viewer_client.dart';

typedef ViewerClientFactory = ViewerClient Function({
  required String host,
  required int port,
  required String fingerprint,
  String? token,
});

/// How the app reaches a viewer listener; overridden in tests with a fake
/// transport.
final viewerClientFactoryProvider = Provider<ViewerClientFactory>(
  (_) => ({required host, required port, required fingerprint, token}) =>
      ViewerClient(host: host, port: port, fingerprint: fingerprint, token: token),
);

final pairingServiceProvider = Provider<PairingService>(
  (ref) => PairingService(
    clientFor: ref.watch(viewerClientFactoryProvider),
    keys: ref.watch(deviceKeyStoreProvider),
    store: (host) => ref.read(pairedHostsProvider.notifier).add(host),
  ),
);

/// The name the computer lists this device under ("Paired devices").
String defaultDeviceName() {
  if (Platform.isIOS) return 'AgentMux Mobile (iOS)';
  if (Platform.isAndroid) return 'AgentMux Mobile (Android)';
  return 'AgentMux Mobile';
}

/// Pairs this device with the computer a scanned [PairCode] names
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 13.2, 13.4): posts
/// the one-time code over TLS pinned to the code's fingerprint, then stores
/// the viewer token it gets back. It makes this device's key for the pairing
/// first and sends its public half, which is what lets the computer check a
/// message sent from this phone (`SPEC_SEND_FROM_THE_PHONE_2026_10_13.md`
/// 5.2.1). A device with no key store, or a computer too old to take the
/// key, still pairs, for watching.
class PairingService {
  PairingService({
    required this.clientFor,
    required this.store,
    this.keys = const NoDeviceKeyStore(),
    Random? random,
  }) : _random = random ?? Random.secure();

  final ViewerClientFactory clientFor;
  final DeviceKeyStore keys;
  final Future<void> Function(PairedHost) store;
  final Random _random;

  /// Throws [PairingException] when the computer refuses or cannot be
  /// reached; nothing is stored then.
  Future<PairedHost> pair(PairCode code, {String? deviceName}) async {
    final id = _newId();
    final alias = deviceKeyAlias(id);
    String? deviceKey;
    try {
      deviceKey = base64.encode(await keys.create(alias));
    } on Object catch (e) {
      // Pairs for watching only: no key, no sending.
      AppLogger.log('No device key: ${e.runtimeType}', name: 'Pairing');
    }
    PairResult result;
    try {
      try {
        result = await _post(code, deviceName, deviceKey);
      } on PairingException catch (e) {
        if (e.failure != PairingFailure.deviceKeyRefused) rethrow;
        // An older computer takes only a 32-byte key and says so before it
        // uses the code: the same request without one pairs for watching.
        deviceKey = null;
        await _forget(alias);
        result = await _post(code, deviceName, null);
      }
    } on Object {
      await _forget(alias);
      rethrow;
    }
    final host = PairedHost(
      id: id,
      token: result.token,
      fingerprint: code.fingerprint,
      host: code.host,
      port: code.port,
      hostname: result.hostname ?? code.hostname ?? code.host,
      channel: result.channel ?? code.channel,
      installId: result.installId,
      deviceId: result.deviceId,
      pairedAt: clock.now(),
    );
    await store(host);
    // States and names only, never the token or the code.
    AppLogger.log('Paired with ${host.hostname}', name: 'Pairing');
    return host;
  }

  Future<PairResult> _post(PairCode code, String? deviceName, String? deviceKey) async {
    final client = clientFor(
      host: code.host,
      port: code.port,
      fingerprint: code.fingerprint,
    );
    try {
      return await client.pair(
        code: code.code,
        deviceName: deviceName ?? defaultDeviceName(),
        deviceKey: deviceKey,
      );
    } finally {
      client.close();
    }
  }

  /// Best effort: a key that stays does no harm, it is never used.
  Future<void> _forget(String alias) async {
    try {
      await keys.delete(alias);
    } on Object catch (e) {
      AppLogger.log('Could not remove a device key: ${e.runtimeType}', name: 'Pairing');
    }
  }

  String _newId() => [
        for (var i = 0; i < 8; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
}
