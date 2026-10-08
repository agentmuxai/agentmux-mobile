import 'dart:async';
import 'dart:io';

import 'package:agentmux_mobile/core/discovery/bonjour_scanner.dart';
import 'package:agentmux_mobile/core/discovery/discovery_telemetry.dart';
import 'package:agentmux_mobile/core/discovery/lan_scanner.dart';
import 'package:agentmux_mobile/core/discovery/mdns_scanner.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Placeholder values only: documentation addresses, made-up ids.
const _installId = 'testinstallidtestinstallid';

const _txt = {
  'auth_key': 'lan-a',
  'version': '0.60.0',
  'hostname': 'host-a',
  'channel': 'stable',
  'os': 'macos',
  'install_id': _installId,
  'instance_id': '0.60.0',
};

BonjourServiceResolved _resolved({
  String name = 'AgentMux on host-a',
  String? host = 'host-a.local.',
  int port = 29700,
  Map<String, String> attributes = _txt,
}) =>
    BonjourServiceResolved(
      name: name,
      host: host,
      port: port,
      attributes: attributes,
    );

/// Answers every host with the addresses in [table]; an unknown host fails
/// as the system resolver would.
AddressLookup _lookupFrom(Map<String, List<String>> table) => (host) async {
      final addresses = table[host];
      if (addresses == null) throw SocketException('no such host $host');
      return [for (final a in addresses) InternetAddress(a)];
    };

final _lookup = _lookupFrom({
  'host-a.local': ['198.51.100.7'],
});

/// Plays a scripted browse, and records whether it was cancelled (which is
/// what stops the platform browser).
class _FakeBrowser implements BonjourBrowser {
  _FakeBrowser(this.events, {this.error, this.keepOpen = false});
  final List<BonjourEvent> events;
  final Object? error;
  final bool keepOpen;
  final types = <String>[];
  var cancelled = false;

  @override
  Stream<BonjourEvent> browse(String type) {
    types.add(type);
    late final StreamController<BonjourEvent> c;
    c = StreamController<BonjourEvent>(
      onListen: () {
        final e = error;
        if (e != null) {
          c.addError(e);
          c.close();
          return;
        }
        events.forEach(c.add);
        if (!keepOpen) c.close();
      },
      onCancel: () => cancelled = true,
    );
    return c.stream;
  }
}

void main() {
  setUp(DiscoveryTelemetry.reset);

  group('BonjourScanner.resolveInstance', () {
    test('a resolved service becomes the LanInstance mDNS would build',
        () async {
      final outcome = await BonjourScanner.resolveInstance(_resolved(), _lookup);
      expect(outcome.discardReason, isNull);
      expect(
        outcome.instance,
        const LanInstance(
          hostname: 'host-a',
          version: '0.60.0',
          // From resolving the SRV target, never from TXT.
          address: '198.51.100.7',
          // From the SRV record.
          port: 29700,
          authKey: 'lan-a',
          instanceId: '0.60.0',
          channel: 'stable',
          os: 'macos',
          installId: _installId,
        ),
      );
    });

    test('the port and address come from the resolution', () async {
      final outcome = await BonjourScanner.resolveInstance(
        _resolved(host: 'host-b.local.', port: 29704),
        _lookupFrom({
          'host-b.local': ['198.51.100.9'],
        }),
      );
      expect(outcome.instance!.port, 29704);
      expect(outcome.instance!.address, '198.51.100.9');
    });

    test('IPv4 is preferred; IPv6 only when there is no IPv4', () async {
      final both = await BonjourScanner.resolveInstance(
        _resolved(),
        _lookupFrom({
          'host-a.local': ['2001:db8::7', '198.51.100.7'],
        }),
      );
      expect(both.instance!.address, '198.51.100.7');
      final v6 = await BonjourScanner.resolveInstance(
        _resolved(),
        _lookupFrom({
          'host-a.local': ['2001:db8::7'],
        }),
      );
      expect(v6.instance!.address, '2001:db8::7');
    });

    test('a host that already is an address is not looked up', () async {
      final outcome = await BonjourScanner.resolveInstance(
        _resolved(host: '198.51.100.12'),
        (_) => throw StateError('no lookup expected'),
      );
      expect(outcome.instance!.address, '198.51.100.12');
    });

    test('without a hostname in TXT, the SRV target names the host', () async {
      final outcome = await BonjourScanner.resolveInstance(
        _resolved(attributes: const {'auth_key': 'lan-a'}),
        _lookup,
      );
      expect(outcome.instance!.hostname, 'host-a');
      expect(outcome.instance!.version, '?');
    });

    test('a TXT record without auth_key is dropped', () async {
      final outcome = await BonjourScanner.resolveInstance(
        _resolved(attributes: const {'version': '0.60.0', 'hostname': 'host-a'}),
        _lookup,
      );
      expect(outcome.instance, isNull);
      expect(outcome.discardReason, 'missing auth_key TXT field');
    });

    test('a malformed os or install_id is dropped, the instance kept',
        () async {
      final outcome = await BonjourScanner.resolveInstance(
        _resolved(attributes: const {
          'auth_key': 'lan-a',
          'os': 'Mac OS X',
          'install_id': 'a b c',
        }),
        _lookup,
      );
      expect(outcome.instance!.os, isNull);
      expect(outcome.instance!.installId, isNull);
    });

    test('no host or no port is dropped as a missing SRV record', () async {
      for (final s in [_resolved(host: null), _resolved(port: 0)]) {
        final outcome = await BonjourScanner.resolveInstance(s, _lookup);
        expect(outcome.discardReason, 'missing SRV record');
      }
    });

    test('a host that does not resolve is dropped', () async {
      final outcome = await BonjourScanner.resolveInstance(
        _resolved(host: 'host-z.local.'),
        _lookup,
      );
      expect(outcome.discardReason, 'no resolvable A/AAAA record');
    });
  });

  test('parseTxtAttributes applies parseTxt\'s rules to a key/value map', () {
    final fromMap = MdnsScanner.parseTxtAttributes(_txt);
    final fromText = MdnsScanner.parseTxt(
      [for (final e in _txt.entries) '${e.key}=${e.value}'].join('\n'),
    );
    expect(fromMap, fromText);
    // A value cannot smuggle in another key through a line break.
    expect(
      MdnsScanner.parseTxtAttributes(const {'version': '1\nauth_key=x'})
          .authKey,
      isNull,
    );
  });

  group('BonjourScanner.scan', () {
    test('browses _agentmux._tcp and yields each valid service', () async {
      final browser = _FakeBrowser([
        const BonjourServiceFound('AgentMux on host-a'),
        _resolved(),
        const BonjourServiceFound('bad'),
        _resolved(name: 'bad', attributes: const {'version': '1'}),
        const BonjourServiceFound('unresolvable'),
        const BonjourResolveFailed(),
      ]);
      final scanner = BonjourScanner(browser: browser, lookup: _lookup);
      final found = await scanner.scan(logSummary: false).toList();

      expect(browser.types, ['_agentmux._tcp']);
      expect(found.map((i) => (i.hostname, i.address, i.port)), [
        ('host-a', '198.51.100.7', 29700),
      ]);
      final summary = DiscoveryTelemetry.lastMdnsSummary!;
      expect(summary.layer, 'bonjour');
      expect(summary.outcome, 'results');
      expect(summary.detail, contains('3 service(s) seen, 1 resolved'));
      expect(summary.detail, contains('1 missing auth_key TXT field'));
      expect(summary.detail, contains('1 resolve failed'));
    });

    test('cancelling the scan stops the browse', () async {
      final browser = _FakeBrowser([_resolved()], keepOpen: true);
      final scanner = BonjourScanner(browser: browser, lookup: _lookup);
      final first = await scanner.scan(logSummary: false).first;
      expect(first.address, '198.51.100.7');
      expect(browser.cancelled, isTrue);
    });

    test('a browse that cannot start yields nothing and says why', () async {
      final scanner = BonjourScanner(
        browser: _FakeBrowser(const [], error: StateError('NoAuth')),
        lookup: _lookup,
      );
      expect(await scanner.scan(logSummary: false).toList(), isEmpty);
      expect(DiscoveryTelemetry.lastMdnsSummary!.outcome, 'error');
      expect(DiscoveryTelemetry.lastMdnsSummary!.detail, contains('NoAuth'));
    });
  });

  group('platform choice', () {
    test('iOS browses with Bonjour and skips the UDP probe', () {
      expect(lanBrowseMethodFor(TargetPlatform.iOS), LanBrowseMethod.bonjour);
      expect(udpProbeSupportedOn(TargetPlatform.iOS), isFalse);
    });

    test('Android and the rest keep multicast_dns and the UDP probe', () {
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(lanBrowseMethodFor(p), LanBrowseMethod.multicastDns);
        expect(udpProbeSupportedOn(p), isTrue);
      }
    });
  });
}
