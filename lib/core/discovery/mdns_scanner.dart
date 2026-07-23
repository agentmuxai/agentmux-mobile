import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import '../logging/app_logger.dart';
import 'android_multicast_lock.dart';
import 'models/lan_instance.dart';

const _serviceType = '_agentmux._tcp.local';

class MdnsScanner {
  Stream<LanInstance> scan() async* {
    final client = MDnsClient();
    await AndroidMulticastLock.acquire();
    try {
      await client.start();

      await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceType))) {
        final instance = await _resolveService(client, ptr.domainName);
        if (instance != null) yield instance;
      }
    } catch (e, stackTrace) {
      // mDNS unavailable (no WiFi, permission denied, or a platform-level
      // socket setup failure) — the scan stream just emits nothing rather
      // than surfacing an error to the UI (manual entry / QR / UDP
      // broadcast are the designed fallbacks — see discovery_provider.dart),
      // but log it so a real regression isn't silently invisible.
      //
      // Note: on x86_64 Android emulators, `MDnsClient.start()` (which
      // hardcodes `reusePort: true` — see the `multicast_dns` package
      // source) triggers a native "Dart Socket ERROR: ... `reusePort` not
      // supported on this platform" line in logcat. That's the Dart
      // runtime's native socket layer logging a best-effort setsockopt
      // failure directly, not a thrown Dart exception — it never reaches
      // this catch block, and manual emulator testing confirmed the scan
      // still completes normally (bind succeeds without SO_REUSEPORT)
      // despite it. Safe to ignore; documented here so it isn't
      // re-investigated as a mystery next time someone sees it in logcat.
      AppLogger.log(
        'mDNS scan failed, discovery falls back to manual/QR/UDP broadcast',
        name: 'MdnsScanner',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      client.stop();
      await AndroidMulticastLock.release();
    }
  }

  Future<LanInstance?> _resolveService(
      MDnsClient client, String serviceName) async {
    String? host;
    int? port;
    String? authKey;
    String? version;
    String? hostname;
    String? instanceId;

    // SRV → host + port
    await for (final srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(serviceName))) {
      host = srv.target;
      port = srv.port;
      break;
    }
    if (host == null || port == null) return null;

    // TXT → metadata
    await for (final txt in client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(serviceName))) {
      for (final kv in txt.text.split('\n')) {
        final idx = kv.indexOf('=');
        if (idx < 0) continue;
        final k = kv.substring(0, idx).trim();
        final v = kv.substring(idx + 1).trim();
        switch (k) {
          case 'auth_key':
            authKey = v;
          case 'version':
            version = v;
          case 'hostname':
            hostname = v;
          case 'instance_id':
            instanceId = v;
        }
      }
      break;
    }
    if (authKey == null) return null;

    // A → IP
    String? address;
    await for (final ip in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(host))) {
      address = ip.address.address;
      break;
    }
    // fallback to IPv6
    if (address == null) {
      await for (final ip in client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv6(host))) {
        address = ip.address.address;
        break;
      }
    }
    if (address == null) return null;

    return LanInstance(
      hostname: hostname ?? host.split('.').first,
      version: version ?? '?',
      address: address,
      port: port,
      authKey: authKey,
      instanceId: instanceId,
    );
  }
}
