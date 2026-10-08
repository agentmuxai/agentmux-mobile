import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/core/viewer/paired_match.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewer_fakes.dart';

FleetEntry _lan({
  String hostname = 'host-a',
  String channel = 'stable',
  String address = '198.51.100.20',
  int port = 29700,
  String? installId = testInstallId,
  int? viewerPort,
  List<LanAgent> agents = const [LanAgent(name: 'AgentA')],
}) =>
    FleetEntry(
      instance: LanInstance(
        hostname: hostname,
        version: '0.60.0',
        address: address,
        port: port,
        authKey: 'k',
        channel: channel,
        installId: installId,
        viewerPort: viewerPort,
        agents: agents,
      ),
    );

FleetEntry _cloud({String id = testInstallId}) => FleetEntry(
      instance: LanInstance(
        hostname: 'host-a',
        version: '0.60.0',
        address: '',
        port: 0,
        authKey: '',
        channel: 'stable',
        installId: id,
        agents: const [LanAgent(name: 'AgentA')],
      ),
      route: ChannelRoute.cloud,
    );

ChannelNode _only(List<FleetEntry> entries) =>
    buildHostTrees(entries).single.channels.single;

void main() {
  test('matched by install id, whatever the names', () {
    final c = _only([_lan(hostname: 'renamed', channel: 'renamed')]);
    final m = matchPairing(c, [testPairedHost()]);
    expect(m?.paired.id, 'p1');
  });

  test('without an install id, by hostname (any case) and channel', () {
    final c = _only([_lan(hostname: 'HOST-A', installId: null)]);
    expect(matchPairing(c, [testPairedHost(installId: null)]), isNotNull);
    expect(matchPairing(c, [testPairedHost()]), isNotNull);
    expect(
      matchPairing(c, [testPairedHost(installId: null, channel: 'dev')]),
      isNull,
    );
    expect(
      matchPairing(c, [testPairedHost(installId: null, hostname: 'host-b')]),
      isNull,
    );
  });

  test('two different install ids never match by name', () {
    final c = _only([_lan(installId: 'anotherinstallanotherinst')]);
    expect(matchPairing(c, [testPairedHost()]), isNull);
  });

  test('discovery\'s address and viewer_port win over the stored ones', () {
    final c = _only([_lan(address: '198.51.100.44', viewerPort: 29811)]);
    final m = matchPairing(c, [testPairedHost()])!;
    expect((m.host, m.port), ('198.51.100.44', 29811));
    expect(m.moved, isTrue);

    final same = matchPairing(
      _only([_lan(viewerPort: 29800)]),
      [testPairedHost()],
    )!;
    expect(same.moved, isFalse);
  });

  test('no viewer_port reported: the stored port stays', () {
    final m = matchPairing(_only([_lan()]), [testPairedHost()])!;
    expect(m.port, 29800);
  });

  test('a channel only a sibling reported: same machine address, stored port',
      () {
    // The stable channel's instance reports a `dev` agent; dev itself was
    // not discovered, so its node carries stable's instance.
    final host = buildHostTrees([
      _lan(
        viewerPort: 29811,
        agents: const [
          LanAgent(name: 'AgentA'),
          LanAgent(name: 'AgentD', channel: 'dev'),
        ],
      ),
    ]).single;
    final dev = host.channels.firstWhere((c) => c.name == 'dev');
    final paired = testPairedHost(
      id: 'dev',
      channel: 'dev',
      installId: 'devinstalldevinstalldevins',
      port: 29900,
    );
    final m = matchPairing(dev, [paired])!;
    expect(m.host, '198.51.100.20');
    expect(m.port, 29900);
  });

  test('a cloud-only channel is never matched', () {
    final c = _only([_cloud()]);
    expect(c.cloudOnly, isTrue);
    expect(matchPairing(c, [testPairedHost()]), isNull);
  });

  test('applyPairings fills in each channel, each pairing once', () {
    final hosts = buildHostTrees([
      _lan(),
      _lan(channel: 'dev', port: 29701, installId: 'devinstalldevinstalldevins'),
    ]);
    final paired = applyPairings(hosts, [testPairedHost()]);
    final channels = paired.single.channels;
    expect(channels.firstWhere((c) => c.name == 'stable').pairing, isNotNull);
    expect(channels.firstWhere((c) => c.name == 'dev').pairing, isNull);
    // Without pairings the trees are returned as they are.
    expect(applyPairings(hosts, const []), same(hosts));
  });

  group('a paired computer discovery has not found', () {
    FleetEntry pairedOnly({String id = 'p1', String channel = 'stable'}) =>
        FleetEntry(
          instance: LanInstance(
            hostname: 'host-a',
            version: '0.60.0',
            address: '198.51.100.20',
            port: 29800,
            authKey: '',
            channel: channel,
            installId: testInstallId,
            viewerPort: 29800,
            agents: const [LanAgent(name: 'AgentA')],
          ),
          pairedId: id,
        );

    test('carries its own pairing, at the stored listener', () {
      final hosts = applyPairings(
        buildHostTrees([pairedOnly()]),
        [testPairedHost()],
      );
      final c = hosts.single.channels.single;
      expect(c.pairedId, 'p1');
      expect(c.pairing!.paired.id, 'p1');
      expect((c.pairing!.host, c.pairing!.port), ('198.51.100.20', 29800));
      expect(c.pairing!.moved, isFalse);
    });

    test('never takes over a discovered channel of the same name', () {
      // Two installs on one machine, both "stable": the discovered one is
      // not this pairing's (different install id).
      final hosts = applyPairings(
        buildHostTrees([
          _lan(installId: 'otherinstallotherinstallot'),
          pairedOnly(),
        ]),
        [testPairedHost()],
      );
      final channels = hosts.single.channels;
      expect(channels, hasLength(2));
      expect(channels.where((c) => c.pairedId == 'p1'), hasLength(1));
      expect(
        channels.firstWhere((c) => c.pairedId == null).pairing,
        isNull,
      );
    });

    test('once unpaired, it is matched to no other pairing', () {
      final hosts = applyPairings(
        buildHostTrees([pairedOnly()]),
        [testPairedHost(id: 'p2', installId: null)],
      );
      expect(hosts.single.channels.single.pairing, isNull);
    });

    test('joins the cloud record of its install', () {
      final c = _only([pairedOnly(), _cloud()]);
      expect(c.cloudOnly, isFalse);
      expect(c.pairedId, 'p1');
    });
  });
}
