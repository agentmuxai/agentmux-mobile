import 'package:flutter_test/flutter_test.dart';
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
}
