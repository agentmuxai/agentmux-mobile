import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'models/lan_instance.dart';

const _serviceType = '_agentmux._tcp.local';

class MdnsScanner {
  Stream<LanInstance> scan() async* {
    final client = MDnsClient();
    try {
      await client.start();

      await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceType))) {
        final instance = await _resolveService(client, ptr.domainName);
        if (instance != null) yield instance;
      }
    } catch (_) {
      // mDNS unavailable (no WiFi, permission denied) — emit nothing
    } finally {
      client.stop();
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
