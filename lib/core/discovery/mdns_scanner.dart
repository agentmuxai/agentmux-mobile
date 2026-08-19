import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import '../logging/app_logger.dart';
import 'android_multicast_lock.dart';
import 'discovery_telemetry.dart';
import 'models/lan_instance.dart';

const _serviceType = '_agentmux._tcp.local';

/// Outcome of resolving one PTR record's full service chain (SRV → TXT →
/// A/AAAA). Distinguishing success from *why* a record was discarded is
/// what tells apart "a host advertised but its record was incomplete" from
/// "nothing advertised at all" — see
/// docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md. Internal to this file;
/// `scan()` unwraps it into the public `LanInstance` stream and tallies
/// [discardReason] for the end-of-scan summary log.
class _ResolveOutcome {
  const _ResolveOutcome.success(this.instance) : discardReason = null;
  const _ResolveOutcome.discarded(this.discardReason) : instance = null;

  final LanInstance? instance;
  final String? discardReason;
}

class MdnsScanner {
  Stream<LanInstance> scan() async* {
    final client = MDnsClient();
    await AndroidMulticastLock.acquire();
    final stopwatch = Stopwatch()..start();
    var ptrCount = 0;
    var resolvedCount = 0;
    final discardTally = <String, int>{};
    String? errorDetail;
    try {
      await client.start();

      await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceType))) {
        ptrCount++;
        final result = await _resolveService(client, ptr.domainName);
        if (result.instance != null) {
          resolvedCount++;
          yield result.instance!;
        } else if (result.discardReason != null) {
          discardTally.update(result.discardReason!, (n) => n + 1,
              ifAbsent: () => 1);
        }
      }
      // NOT "await for completed, so record the outcome here" — this point
      // is only reached if the mDNS lookup stream ends on its own. In real
      // usage it never does: the caller's `.timeout()` wrapper
      // (discovery_provider.dart) always ends this scan via external
      // cancellation, which unwinds straight past this line to `finally`
      // (reagent P1 on PR #17 — an earlier version set `outcome` here and
      // it silently never ran, leaving `outcome` stuck at its initial
      // 'empty' default even when instances WERE resolved). `outcome` is
      // instead derived in `finally`, from `resolvedCount`/`errorDetail`
      // directly — values that ARE updated correctly regardless of how the
      // generator exits.
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
      errorDetail = e.toString();
      AppLogger.log(
        'mDNS scan failed, discovery falls back to manual/QR/UDP broadcast',
        name: 'MdnsScanner',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      client.stop();
      await AndroidMulticastLock.release();

      // Unconditional summary — this is the fix for the actual gap: a scan
      // that completes cleanly with zero results previously logged nothing
      // at all, indistinguishable in the debug log from "never ran." Derived
      // here (not earlier in `try`) so it's correct regardless of whether
      // this generator exits via natural completion, external cancellation,
      // or an exception — see the comment above the `await for` loop.
      final outcome =
          errorDetail != null ? 'error' : (resolvedCount > 0 ? 'results' : 'empty');
      final discardText = discardTally.isEmpty
          ? ''
          : ' (${discardTally.entries.map((e) => '${e.value} ${e.key}').join(', ')})';
      final detail = outcome == 'error'
          ? 'failed: $errorDetail'
          : '$ptrCount PTR record(s) seen, $resolvedCount resolved$discardText '
              'in ${stopwatch.elapsedMilliseconds}ms';
      AppLogger.log('mDNS scan complete: $detail', name: 'MdnsScanner');
      DiscoveryTelemetry.lastMdnsSummary = ScanSummary(
        layer: 'mdns',
        outcome: outcome,
        detail: detail,
        at: DateTime.now(),
      );
    }
  }

  Future<_ResolveOutcome> _resolveService(
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
    if (host == null || port == null) {
      return const _ResolveOutcome.discarded('missing SRV record');
    }

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
    if (authKey == null) {
      return const _ResolveOutcome.discarded('missing auth_key TXT field');
    }

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
    if (address == null) {
      return const _ResolveOutcome.discarded('no resolvable A/AAAA record');
    }

    return _ResolveOutcome.success(LanInstance(
      hostname: hostname ?? host.split('.').first,
      version: version ?? '?',
      address: address,
      port: port,
      authKey: authKey,
      instanceId: instanceId,
    ));
  }
}
