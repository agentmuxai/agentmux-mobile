import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import 'discovery_telemetry.dart';
import 'lan_scanner.dart';
import 'mdns_scanner.dart';
import 'models/lan_instance.dart';

/// The service type as Bonjour names it (no `.local`).
const bonjourServiceType = '_agentmux._tcp';

/// One step of a Bonjour browse, as a [BonjourBrowser] reports it.
sealed class BonjourEvent {
  const BonjourEvent();
}

/// A service was seen; resolving it has started.
class BonjourServiceFound extends BonjourEvent {
  const BonjourServiceFound(this.name);
  final String name;
}

/// A service was resolved: its SRV target and port, and its TXT record.
class BonjourServiceResolved extends BonjourEvent {
  const BonjourServiceResolved({
    required this.name,
    required this.host,
    required this.port,
    required this.attributes,
  });
  final String name;

  /// The SRV target, e.g. `host-a.local.`; null when the platform gave none.
  final String? host;
  final int port;
  final Map<String, String> attributes;
}

/// A service was seen but could not be resolved.
class BonjourResolveFailed extends BonjourEvent {
  const BonjourResolveFailed();
}

/// Browses for one service type with the platform's Bonjour API and resolves
/// every service it finds. Cancelling the stream stops the browse. The
/// stream errors if the browse cannot start.
abstract class BonjourBrowser {
  Stream<BonjourEvent> browse(String type);
}

/// Resolves a host name to its addresses (the system resolver, which answers
/// `.local` names through mDNSResponder on iOS); replaced in tests.
typedef AddressLookup = Future<List<InternetAddress>> Function(String host);

Future<List<InternetAddress>> _systemLookup(String host) =>
    InternetAddress.lookup(host);

/// Why a resolved service was not turned into a [LanInstance], or the
/// instance it became.
class BonjourResolveOutcome {
  const BonjourResolveOutcome.success(LanInstance this.instance)
      : discardReason = null;
  const BonjourResolveOutcome.discarded(String this.discardReason)
      : instance = null;

  final LanInstance? instance;
  final String? discardReason;
}

/// LAN discovery through the platform's Bonjour browser (iOS).
///
/// On a real iOS device, raw multicast (`multicast_dns`) and UDP broadcast
/// need Apple's restricted multicast entitlement; the system's own Bonjour
/// browser does not, as long as Info.plist lists `_agentmux._tcp` under
/// `NSBonjourServices`. Each resolved service becomes the same [LanInstance]
/// `MdnsScanner` builds: the TXT record parsed by `MdnsScanner.parseTxt`'s
/// rules, the port from the SRV record, the address from resolving its host.
class BonjourScanner implements LanScanner {
  BonjourScanner({
    BonjourBrowser? browser,
    AddressLookup? lookup,
  })  : _browser = browser ?? BonsoirBrowser(),
        _lookup = lookup ?? _systemLookup;

  final BonjourBrowser _browser;
  final AddressLookup _lookup;

  /// How long one host name may take to resolve.
  static const lookupTimeout = Duration(seconds: 3);

  @override
  Stream<LanInstance> scan({bool logSummary = true}) async* {
    final stopwatch = Stopwatch()..start();
    var found = 0;
    var resolved = 0;
    final discardTally = <String, int>{};
    String? errorDetail;
    void discard(String reason) =>
        discardTally.update(reason, (n) => n + 1, ifAbsent: () => 1);
    try {
      await for (final event in _browser.browse(bonjourServiceType)) {
        switch (event) {
          case BonjourServiceFound():
            found++;
          case BonjourResolveFailed():
            discard('resolve failed');
          case BonjourServiceResolved():
            final outcome = await resolveInstance(event, _lookup);
            final instance = outcome.instance;
            if (instance != null) {
              resolved++;
              yield instance;
            } else {
              discard(outcome.discardReason!);
            }
        }
      }
    } catch (e, stackTrace) {
      // Same contract as MdnsScanner: a browse that cannot run yields
      // nothing (QR and manual entry are the fallbacks), and says why.
      errorDetail = e.toString();
      AppLogger.log(
        'Bonjour browse failed, discovery falls back to manual/QR',
        name: 'BonjourScanner',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      // Derived here, not in `try`: the caller ends a scan by cancelling it,
      // which skips straight to `finally` (see MdnsScanner.scan).
      final outcome = errorDetail != null
          ? 'error'
          : (resolved > 0 ? 'results' : 'empty');
      final discardText = discardTally.isEmpty
          ? ''
          : ' (${discardTally.entries.map((e) => '${e.value} ${e.key}').join(', ')})';
      final detail = outcome == 'error'
          ? 'Bonjour failed: $errorDetail'
          : 'Bonjour, $found service(s) seen, $resolved resolved$discardText '
              'in ${stopwatch.elapsedMilliseconds}ms';
      if (logSummary) {
        AppLogger.log('Bonjour scan complete: $detail', name: 'BonjourScanner');
      }
      DiscoveryTelemetry.lastMdnsSummary = ScanSummary(
        layer: 'bonjour',
        outcome: outcome,
        detail: detail,
        at: DateTime.now(),
      );
    }
  }

  /// The [LanInstance] for one resolved service, or why it was dropped: the
  /// same reasons, in the same order, as `MdnsScanner` (SRV, then TXT, then
  /// the address).
  @visibleForTesting
  static Future<BonjourResolveOutcome> resolveInstance(
    BonjourServiceResolved service,
    AddressLookup lookup,
  ) async {
    final target = _trimDot(service.host ?? '');
    final port = service.port;
    if (target.isEmpty || port <= 0 || port > 65535) {
      return const BonjourResolveOutcome.discarded('missing SRV record');
    }
    final txt = MdnsScanner.parseTxtAttributes(service.attributes);
    final authKey = txt.authKey;
    if (authKey == null) {
      return const BonjourResolveOutcome.discarded(
          'missing auth_key TXT field');
    }
    final address = await _address(target, lookup);
    if (address == null) {
      return const BonjourResolveOutcome.discarded(
          'no resolvable A/AAAA record');
    }
    return BonjourResolveOutcome.success(lanInstanceFromService(
      txt: txt,
      authKey: authKey,
      srvTarget: target,
      port: port,
      address: address,
    ));
  }

  /// The host's IPv4 address, else its IPv6 one (as MdnsScanner prefers A
  /// over AAAA); the host itself when it already is an address.
  static Future<String?> _address(String host, AddressLookup lookup) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal.address;
    final List<InternetAddress> found;
    try {
      found = await lookup(host).timeout(lookupTimeout);
    } catch (_) {
      return null;
    }
    for (final a in found) {
      if (a.type == InternetAddressType.IPv4) return a.address;
    }
    for (final a in found) {
      if (a.type == InternetAddressType.IPv6) return a.address;
    }
    return null;
  }

  static String _trimDot(String host) =>
      host.endsWith('.') ? host.substring(0, host.length - 1) : host;
}

/// [BonjourBrowser] over the `bonsoir` plugin: NWBrowser to find services
/// (with their TXT records) and DNSServiceResolve for host and port on iOS.
class BonsoirBrowser implements BonjourBrowser {
  @override
  Stream<BonjourEvent> browse(String type) {
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    var cancelled = false;
    late final StreamController<BonjourEvent> out;

    Future<void> stop() async {
      await sub?.cancel();
      sub = null;
      final d = discovery;
      discovery = null;
      if (d != null && !d.isStopped) {
        try {
          await d.stop();
        } catch (_) {
          // Already stopped by the platform.
        }
      }
    }

    void onEvent(BonsoirDiscoveryEvent event) {
      final d = discovery;
      if (d == null || out.isClosed) return;
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          out.add(BonjourServiceFound(service.name));
          unawaited(d.serviceResolver
              .resolveService(service)
              .catchError((Object _) {
            if (!out.isClosed) out.add(const BonjourResolveFailed());
          }));
        case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
              BonsoirDiscoveryServiceUpdatedEvent(:final service):
          // An update before the service was resolved has no host yet;
          // its resolution follows.
          if (service.host == null &&
              event is BonsoirDiscoveryServiceUpdatedEvent) {
            return;
          }
          out.add(BonjourServiceResolved(
            name: service.name,
            host: service.host,
            port: service.port,
            attributes: service.attributes,
          ));
        case BonsoirDiscoveryServiceResolveFailedEvent():
          out.add(const BonjourResolveFailed());
        default:
          break;
      }
    }

    out = StreamController<BonjourEvent>(
      onListen: () async {
        try {
          final d = BonsoirDiscovery(type: type, printLogs: false);
          discovery = d;
          await d.initialize();
          if (cancelled) return stop();
          sub = d.eventStream?.listen(
            onEvent,
            onError: (Object e, StackTrace st) {
              if (!out.isClosed) out.addError(e, st);
            },
          );
          await d.start();
        } catch (e, st) {
          await stop();
          if (!out.isClosed) {
            out.addError(e, st);
            await out.close();
          }
        }
      },
      onCancel: () {
        cancelled = true;
        return stop();
      },
    );
    return out.stream;
  }
}
