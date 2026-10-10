import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/features/discovery/host_card.dart';
import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/channel_session.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';

FleetEntry _instance({
  String hostname = 'narko',
  String address = '192.168.1.50',
  required int port,
  String? channel,
  List<LanAgent> agents = const [],
}) {
  return FleetEntry(
    instance: LanInstance(
      hostname: hostname,
      version: '0.59.7',
      address: address,
      port: port,
      authKey: 'k',
      channel: channel,
      agents: agents,
    ),
  );
}

LanAgent _agent(String name, {String? channel}) =>
    LanAgent(name: name, channel: channel);

void main() {
  group('buildHostTrees', () {
    test('a host with one channel hides the channel level', () {
      final trees = buildHostTrees([
        _instance(port: 29700, agents: [_agent('Opaz')]),
      ]);
      expect(trees, hasLength(1));
      expect(trees.single.name, 'narko');
      expect(trees.single.showChannels, isFalse);
      expect(trees.single.channels.single.agents.map((a) => a.name), ['Opaz']);
    });

    test('two instances on one host are two channels, shown by name', () {
      final trees = buildHostTrees([
        _instance(port: 29704, channel: 'stable', agents: [_agent('Clamk')]),
        _instance(port: 29706, channel: 'dev', agents: [_agent('Korp')]),
      ]);
      expect(trees, hasLength(1));
      final host = trees.single;
      expect(host.showChannels, isTrue);
      // Sorted by name, not discovery order.
      expect(host.channels.map((c) => c.name), ['dev', 'stable']);
      expect(host.channels[0].agents.map((a) => a.name), ['Korp']);
      expect(host.channels[1].agents.map((a) => a.name), ['Clamk']);
    });

    test('a channel the desktop did not name is labelled by its port', () {
      final trees = buildHostTrees([
        _instance(port: 29704),
        _instance(port: 29706),
      ]);
      expect(trees.single.channels.map((c) => c.name), [':29704', ':29706']);
    });

    test('sibling-channel agents become their own channel under the same host',
        () {
      final trees = buildHostTrees([
        _instance(port: 29704, channel: 'stable', agents: [
          _agent('Clamk'),
          _agent('Korp', channel: 'dev'),
        ]),
      ]);
      final host = trees.single;
      expect(host.showChannels, isTrue);
      expect(host.channels.map((c) => c.name), ['dev', 'stable']);
      expect(host.channels[0].agents.map((a) => a.name), ['Korp']);
      // Reached through the instance that reported them.
      expect(host.channels[0].via.port, 29704);
    });

    test('a sibling channel also discovered itself merges, and talks to itself',
        () {
      final trees = buildHostTrees([
        _instance(port: 29704, channel: 'stable', agents: [
          _agent('Clamk'),
          _agent('Korp', channel: 'dev'),
        ]),
        _instance(port: 29706, channel: 'dev', agents: [
          _agent('Korp'),
          _agent('Lark'),
        ]),
      ]);
      final host = trees.single;
      expect(host.channels.map((c) => c.name), ['dev', 'stable']);
      final dev = host.channels[0];
      expect(dev.agents.map((a) => a.name), ['Korp', 'Lark']);
      expect(dev.via.port, 29706);
    });

    test('different hosts stay separate', () {
      final trees = buildHostTrees([
        _instance(hostname: 'charlie', address: '192.168.1.225', port: 29700),
        _instance(hostname: 'starpower', address: '192.168.1.195', port: 29700),
      ]);
      expect(trees.map((t) => t.name), ['charlie', 'starpower']);
      expect(trees.every((t) => !t.showChannels), isTrue);
    });

    test('a host that reports no hostname is grouped by address', () {
      final trees = buildHostTrees([
        _instance(hostname: '', address: '192.168.1.9', port: 29700),
      ]);
      expect(trees.single.name, '192.168.1.9');
    });
    test('hosts, channels and agents are sorted by name, case-insensitively',
        () {
      final trees = buildHostTrees([
        _instance(hostname: 'starpower', address: '192.168.1.195', port: 1),
        _instance(
          hostname: 'Charlie',
          address: '192.168.1.225',
          port: 1,
          agents: [_agent('opaz'), _agent('Agent3'), _agent('beta')],
        ),
      ]);
      expect(trees.map((t) => t.name), ['Charlie', 'starpower']);
      expect(trees.first.channels.single.agents.map((a) => a.name),
          ['Agent3', 'beta', 'opaz']);
    });

    test('presence and errors are carried to the node; a sibling never '
        "inherits its reporter's error", () {
      final trees = buildHostTrees([
        const FleetEntry(
          instance: LanInstance(
            hostname: 'narko',
            version: '0.59.7',
            address: '192.168.1.230',
            port: 29704,
            authKey: 'k',
            channel: 'stable',
            agents: [LanAgent(name: 'Korp', channel: 'dev')],
          ),
          presence: Presence.stale,
          error: ChannelError.unreachable,
        ),
      ]);
      final host = trees.single;
      expect(host.presence, Presence.stale);
      final dev = host.channels.firstWhere((c) => c.name == 'dev');
      final stable = host.channels.firstWhere((c) => c.name == 'stable');
      expect(stable.error, ChannelError.unreachable);
      expect(dev.error, isNull);
      expect(dev.presence, Presence.stale);
    });

    test('a host is live when any of its channels is', () {
      final trees = buildHostTrees([
        _instance(port: 1, channel: 'a'),
        const FleetEntry(
          instance: LanInstance(
            hostname: 'narko',
            version: '0.59.7',
            address: '192.168.1.50',
            port: 2,
            authKey: 'k',
            channel: 'b',
          ),
          presence: Presence.stale,
        ),
      ]);
      expect(trees.single.presence, Presence.live);
    });
  });

  group('buildHostTrees: platform, channel count, route', () {
    FleetEntry entry({
      String hostname = 'narko',
      int port = 29702,
      String? channel = 'local-main',
      String? os,
      int? channelsRunning,
      String? installId,
      List<LanAgent> agents = const [],
      ChannelRoute route = ChannelRoute.lan,
      Presence presence = Presence.live,
      String version = '0.59.11',
    }) =>
        FleetEntry(
          instance: LanInstance(
            hostname: hostname,
            version: version,
            address: route == ChannelRoute.cloud ? '' : '198.51.100.30',
            port: route == ChannelRoute.cloud ? 0 : port,
            authKey: route == ChannelRoute.cloud ? '' : 'k',
            channel: channel,
            os: os,
            channelsRunning: channelsRunning,
            installId: installId,
            agents: agents,
          ),
          route: route,
          presence: presence,
        );

    test('the platform comes from os, and only three values get one', () {
      final trees = buildHostTrees([
        entry(hostname: 'a', os: 'windows'),
        entry(hostname: 'b', os: 'macos'),
        entry(hostname: 'c', os: 'linux'),
        entry(hostname: 'd', os: 'freebsd'),
        entry(hostname: 'e'),
      ]);
      expect(trees.map((t) => t.platform), [
        HostPlatform.windows,
        HostPlatform.macos,
        HostPlatform.linux,
        null,
        null,
      ]);
      expect(trees[3].os, 'freebsd');
    });

    test('channels of one name that disagree on os become one host per os',
        () {
      final trees = buildHostTrees([
        entry(port: 1, channel: 'win', os: 'windows'),
        entry(port: 2, channel: 'wsl', os: 'linux'),
        entry(port: 3, channel: 'old'),
      ]);
      expect(trees, hasLength(3));
      expect(trees.every((t) => t.name == 'narko'), isTrue);
      expect(trees.map((t) => t.key).toSet(), hasLength(3));
      final win = trees.firstWhere((t) => t.platform == HostPlatform.windows);
      expect(win.channels.single.name, 'win');
      final linux = trees.firstWhere((t) => t.platform == HostPlatform.linux);
      expect(linux.channels.single.name, 'wsl');
      final unknown = trees.firstWhere((t) => t.os == null);
      expect(unknown.channels.single.name, 'old');
    });

    test('a channel without os joins its host when the others agree', () {
      final trees = buildHostTrees([
        entry(port: 1, channel: 'a', os: 'windows'),
        entry(port: 2, channel: 'b'),
      ]);
      expect(trees.single.platform, HostPlatform.windows);
      expect(trees.single.channels, hasLength(2));
      expect(trees.single.key, 'host:narko');
    });

    test('showChannels follows channels_running: 1, 3 and absent', () {
      HostNode host(int? running) =>
          buildHostTrees([entry(channelsRunning: running)]).single;

      expect(host(1).showChannels, isFalse);
      expect(host(1).hiddenChannels, 0);
      expect(host(null).showChannels, isFalse);
      expect(host(null).hiddenChannels, 0);
      final three = host(3);
      expect(three.showChannels, isTrue);
      expect(three.hiddenChannels, 2);
    });

    test('absent channels_running keeps the visible-count rule', () {
      final trees = buildHostTrees([
        entry(port: 1, channel: 'a'),
        entry(port: 2, channel: 'b'),
      ]);
      expect(trees.single.showChannels, isTrue);
      expect(trees.single.hiddenChannels, 0);
    });

    test("a host's channel count is the largest any channel reports", () {
      final trees = buildHostTrees([
        entry(port: 1, channel: 'a', channelsRunning: 2),
        entry(port: 2, channel: 'b', channelsRunning: 4),
      ]);
      expect(trees.single.channelsRunning, 4);
      expect(trees.single.hiddenChannels, 2);
    });

    test('route per channel; the host shows one only when they agree', () {
      final same = buildHostTrees([
        entry(port: 1, channel: 'a'),
        entry(port: 2, channel: 'b'),
      ]).single;
      expect(same.route, ChannelRoute.lan);

      final mixed = buildHostTrees([
        entry(port: 1, channel: 'a'),
        entry(channel: 'b', route: ChannelRoute.cloud, installId: 'cccc'),
      ]).single;
      expect(mixed.route, isNull);
      expect(
        {for (final c in mixed.channels) c.name: c.route},
        {'a': ChannelRoute.lan, 'b': ChannelRoute.cloud},
      );
    });

    test('the host version is shown only when every channel agrees', () {
      expect(buildHostTrees([entry()]).single.version, '0.59.11');
      expect(buildHostTrees([entry(version: 'unknown')]).single.version, isNull);
      final differ = buildHostTrees([
        entry(port: 1, channel: 'a', version: '0.59.11'),
        entry(port: 2, channel: 'b', version: '0.59.4'),
      ]).single;
      expect(differ.version, isNull);
    });
  });

  group('buildHostTrees: LAN and cloud', () {
    const id = 'testinstallidtestinstallid';

    FleetEntry lan({
      String? installId = id,
      List<LanAgent> agents = const [LanAgent(name: 'Camper')],
      Presence presence = Presence.live,
      String hostname = 'narko',
      String channel = 'local-main',
    }) =>
        FleetEntry(
          instance: LanInstance(
            hostname: hostname,
            version: '0.59.11',
            address: '198.51.100.30',
            port: 29702,
            authKey: 'k',
            channel: channel,
            installId: installId,
            agents: agents,
          ),
          presence: presence,
          lastSeen: DateTime(2026, 10, 6, 12),
        );

    FleetEntry cloud({
      String instanceId = id,
      String hostname = 'narko',
      String channel = 'local-main',
      List<LanAgent> agents = const [
        LanAgent(name: 'Camper', kind: AgentKind.host),
        LanAgent(name: 'AgentX', kind: AgentKind.container),
      ],
      Presence presence = Presence.live,
      String? os = 'windows',
      int? channelsRunning = 3,
    }) =>
        FleetEntry(
          instance: LanInstance(
            hostname: hostname,
            version: '0.59.11',
            address: '',
            port: 0,
            authKey: '',
            channel: channel,
            os: os,
            channelsRunning: channelsRunning,
            installId: instanceId,
            agents: agents,
          ),
          route: ChannelRoute.cloud,
          presence: presence,
          lastSeen: DateTime(2026, 10, 6, 12, 1),
        );

    test('the same install id is one channel, LAN + Cloud, reached over LAN',
        () {
      final host = buildHostTrees([lan(), cloud()]).single;
      final c = host.channels.single;
      expect(c.route, ChannelRoute.lanAndCloud);
      expect(c.cloudOnly, isFalse);
      expect(c.via.address, '198.51.100.30');
      expect(c.via.port, 29702);
      // The LAN list wins while it answers; kinds come from the cloud.
      expect(c.agents.map((a) => a.name), ['Camper']);
      expect(c.agents.single.kind, AgentKind.host);
      // Platform and count come from whichever source has them.
      expect(host.platform, HostPlatform.windows);
      expect(host.channelsRunning, 3);
      expect(c.lastSeen, DateTime(2026, 10, 6, 12, 1));
    });

    test('when only the cloud is current, its agent list is used', () {
      final c = buildHostTrees([
        lan(presence: Presence.stale),
        cloud(),
      ]).single.channels.single;
      expect(c.agents.map((a) => a.name), ['AgentX', 'Camper']);
      expect(c.route, ChannelRoute.cloud);
      expect(c.presence, Presence.live);
      expect(c.cloudOnly, isFalse, reason: 'it still has its LAN endpoint');
    });

    test('a hostname match alone never merges: two channels, one host', () {
      final host = buildHostTrees([
        lan(installId: 'aaaaaaaaaaaaaaaaaaaaaaaaaa'),
        cloud(),
      ]).single;
      expect(host.name, 'narko');
      expect(host.channels, hasLength(2));
      expect(host.channels.map((c) => c.route).toSet(),
          {ChannelRoute.lan, ChannelRoute.cloud});
      expect(host.channels.map((c) => c.key).toSet(), hasLength(2));
      expect(host.route, isNull);
    });

    test('a LAN record without an install id never merges', () {
      final host = buildHostTrees([lan(installId: null), cloud()]).single;
      expect(host.channels, hasLength(2));
    });

    test('only the first LAN channel claiming an install id takes the cloud '
        'one', () {
      final host = buildHostTrees([
        lan(channel: 'a'),
        lan(channel: 'b'),
        cloud(),
      ]).single;
      expect(host.channels.map((c) => c.route),
          [ChannelRoute.lanAndCloud, ChannelRoute.lan]);
    });

    test('a cloud-only host groups by name like a LAN one', () {
      final trees = buildHostTrees([
        lan(hostname: 'charlie', installId: null),
        cloud(hostname: 'Atlas', os: 'macos', channelsRunning: 1),
      ]);
      expect(trees.map((t) => t.name), ['Atlas', 'charlie']);
      final atlas = trees.first;
      expect(atlas.route, ChannelRoute.cloud);
      expect(atlas.platform, HostPlatform.macos);
      expect(atlas.showChannels, isFalse);
      expect(atlas.channels.single.cloudOnly, isTrue);
    });

    test('a cloud-only agent opens the cloud screen; an unpaired merged one '
        'the pair prompt', () {
      final cloudOnly = buildHostTrees([cloud()]).single.channels.single;
      expect(agentLocation(cloudOnly, cloudOnly.agents.first),
          '/agents/AgentX');
      final merged =
          buildHostTrees([lan(), cloud()]).single.channels.single;
      expect(agentLocation(merged, merged.agents.single),
          '/instance/${Uri.encodeComponent('198.51.100.30:29702')}'
          '/agent/Camper/unpaired');
    });

    test('a merged channel whose LAN side went quiet opens the cloud screen',
        () {
      final c = buildHostTrees([
        lan(presence: Presence.stale),
        cloud(),
      ]).single.channels.single;
      expect(agentLocation(c, c.agents.first), '/agents/AgentX');
    });

    test('live on the LAN with a stale cloud record: not publishing since the '
        'record', () {
      final c = buildHostTrees([lan(), cloud(presence: Presence.stale)])
          .single
          .channels
          .single;
      expect(c.notPublishingSince, DateTime(2026, 10, 6, 12, 1));
      expect(c.route, ChannelRoute.lan);
      expect(c.presence, Presence.live);
      // Kept through pairing, which rebuilds the node.
      expect(c.withPairing(null).notPublishingSince, c.notPublishingSince);
    });

    test('no note while the cloud record is live, the LAN is quiet too, or '
        'the cloud list cannot be read', () {
      ChannelNode only(List<FleetEntry> entries, {bool current = true}) =>
          buildHostTrees(entries, cloudListCurrent: current)
              .single
              .channels
              .single;
      expect(only([lan(), cloud()]).notPublishingSince, isNull);
      expect(
        only([
          lan(presence: Presence.stale),
          cloud(presence: Presence.stale),
        ]).notPublishingSince,
        isNull,
        reason: 'the computer is just off',
      );
      expect(
        only([lan(), cloud(presence: Presence.stale)], current: false)
            .notPublishingSince,
        isNull,
      );
      // A stale install that is not on the LAN is only dimmed.
      expect(only([cloud(presence: Presence.stale)]).notPublishingSince,
          isNull);
    });

    test('a sibling channel never carries the note of the entry that '
        'reported it', () {
      final host = buildHostTrees([
        lan(agents: const [
          LanAgent(name: 'Camper'),
          LanAgent(name: 'Agent3', channel: 'stable'),
        ]),
        cloud(presence: Presence.stale),
      ]).single;
      final byName = {for (final c in host.channels) c.name: c};
      expect(byName['local-main']!.notPublishingSince, isNotNull);
      expect(byName['stable']!.notPublishingSince, isNull);
    });
  });

  group('buildHostTrees: agent states, LAN and cloud', () {
    const id = 'testinstallidtestinstallid';
    final cloudAt = DateTime(2026, 10, 7, 12);
    final lanSince = StateSince(
      elapsedAtReceipt: const Duration(minutes: 3),
      receivedAt: DateTime(2026, 10, 7, 12, 1),
    );

    FleetEntry lan(List<LanAgent> agents, {Presence presence = Presence.live}) =>
        FleetEntry(
          instance: LanInstance(
            hostname: 'narko',
            version: '0.59.11',
            address: '198.51.100.30',
            port: 29702,
            authKey: 'k',
            channel: 'local-main',
            installId: id,
            agents: agents,
          ),
          presence: presence,
        );

    FleetEntry cloud(List<LanAgent> agents, {Presence presence = Presence.live}) =>
        FleetEntry(
          instance: LanInstance(
            hostname: 'narko',
            version: '0.59.11',
            address: '',
            port: 0,
            authKey: '',
            channel: 'local-main',
            installId: id,
            agents: agents,
          ),
          route: ChannelRoute.cloud,
          presence: presence,
        );

    LanAgent fromCloud(String name, AgentState state) =>
        LanAgent(name: name, state: state, stateAsOf: cloudAt);

    test('while the LAN is live its state wins, with its time', () {
      final c = buildHostTrees([
        lan([
          LanAgent(
            name: 'Camper',
            state: AgentState.working,
            stateSince: lanSince,
          ),
        ]),
        cloud([fromCloud('Camper', AgentState.idle)]),
      ]).single.channels.single;
      final a = c.agents.single;
      expect(a.state, AgentState.working);
      expect(a.stateSince, lanSince);
      expect(a.stateAsOf, isNull);
    });

    test('a state the live LAN leaves out is never filled from the cloud', () {
      final c = buildHostTrees([
        lan(const [LanAgent(name: 'Camper')]),
        cloud([fromCloud('Camper', AgentState.working)]),
      ]).single.channels.single;
      expect(c.agents.single.state, isNull);
    });

    test('when only the cloud is current, its states are used', () {
      final c = buildHostTrees([
        lan(
          [
            LanAgent(
              name: 'Camper',
              state: AgentState.working,
              stateSince: lanSince,
            ),
          ],
          presence: Presence.stale,
        ),
        cloud([fromCloud('Camper', AgentState.idle)]),
      ]).single.channels.single;
      final a = c.agents.single;
      expect(a.state, AgentState.idle);
      expect(a.stateAsOf, cloudAt);
      expect(a.stateSince, isNull);
    });

    test('a cloud-only channel shows its own states', () {
      final c = buildHostTrees([
        cloud([fromCloud('Scout', AgentState.waiting)]),
      ]).single.channels.single;
      expect(c.cloudOnly, isTrue);
      expect(c.agents.single.state, AgentState.waiting);
    });

    test('agents stay sorted by name whatever their state', () {
      final c = buildHostTrees([
        lan(const [
          LanAgent(name: 'Zed', state: AgentState.waiting),
          LanAgent(name: 'alpha', state: AgentState.idle),
          LanAgent(name: 'Mid', state: AgentState.working),
        ]),
      ]).single.channels.single;
      expect(c.agents.map((a) => a.name), ['alpha', 'Mid', 'Zed']);
    });
  });
}
