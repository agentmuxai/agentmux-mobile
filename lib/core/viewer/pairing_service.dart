import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
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
/// the viewer token it gets back.
class PairingService {
  PairingService({
    required this.clientFor,
    required this.store,
    Random? random,
  }) : _random = random ?? Random.secure();

  final ViewerClientFactory clientFor;
  final Future<void> Function(PairedHost) store;
  final Random _random;

  /// Throws [PairingException] when the computer refuses or cannot be
  /// reached; nothing is stored then.
  Future<PairedHost> pair(PairCode code, {String? deviceName}) async {
    final client = clientFor(
      host: code.host,
      port: code.port,
      fingerprint: code.fingerprint,
    );
    final PairResult result;
    try {
      result = await client.pair(
        code: code.code,
        deviceName: deviceName ?? defaultDeviceName(),
        // Phase 5 adds `device_key` (optional), from a vetted crypto library.
      );
    } finally {
      client.close();
    }
    final host = PairedHost(
      id: _newId(),
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

  String _newId() => [
        for (var i = 0; i < 8; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
}
