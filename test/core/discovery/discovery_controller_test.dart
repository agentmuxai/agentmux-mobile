import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';
import 'package:agentmux_mobile/core/discovery/mdns_scanner.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/discovery/network_environment.dart';
import 'package:agentmux_mobile/core/discovery/udp_broadcast_prober.dart';
import 'package:agentmux_mobile/core/fleet/fleet_snapshot.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/core/fleet/fleet_transport.dart';

class _FakeMdns extends MdnsScanner {
  @override
  Stream<LanInstance> scan({bool logSummary = true}) => const Stream.empty();
}

class _FakeUdp extends UdpBroadcastProber {
  List<LanInstance> replies = [];

  @override
  Stream<LanInstance> probe({
    Duration timeout = const Duration(seconds: 2),
    bool tryEmulatorRelay = false,
    bool logSummary = true,
  }) =>
      Stream.fromIterable(replies);
}

/// One fake desktop channel per port: streams its agents while alive.
class _FakeHost {
  final agents = <int, List<String>>{};
  final dead = <int>{};
  final open = <int, List<StreamController<FleetSnapshot?>>>{};

  FleetTransport transport(String address, int port, String key) =>
      _HostTransport(this, port);

  void kill(int port) {
    dead.add(port);
    for (final c in open.remove(port) ?? <StreamController<FleetSnapshot?>>[]) {
      c.addError(TimeoutException('silence'));
      c.close();
    }
  }
}

class _HostTransport implements FleetTransport {
  _HostTransport(this.host, this.port);
  final _FakeHost host;
  final int port;

  DioException get _down => DioException(
        requestOptions: RequestOptions(path: '/agentmux/fleet/events'),
        type: DioExceptionType.connectionError,
      );

  @override
  Stream<FleetSnapshot?> events({String? lastEventId}) {
    if (host.dead.contains(port)) return Stream.error(_down);
    final c = StreamController<FleetSnapshot?>();
    host.open.putIfAbsent(port, () => []).add(c);
    c
      ..add(null)
      ..add(FleetSnapshot(
        epoch: 'e$port',
        rev: 1,
        hostname: 'narko',
        version: '0.59.7',
        agents: host.agents[port] ?? const [],
      ));
    return c.stream;
  }

  @override
  Future<FleetPoll> poll({String? etag}) => throw _down;

  @override
  Future<LegacyFleetInfo> legacy() => throw _down;
}

LanInstance _reply(int port, String channel) => LanInstance(
      hostname: 'narko',
      version: '0.59.7',
      address: '192.168.1.230',
      port: port,
      authKey: 'lan-$port',
      channel: channel,
    );

void main() {
  late _FakeUdp udp;
  late _FakeHost host;
  late List<String> interfaces;
  late ProviderContainer container;

  setUp(() {
    udp = _FakeUdp();
    host = _FakeHost();
    interfaces = ['wlan0=192.168.1.50'];
    container = ProviderContainer(overrides: [
      mdnsScannerProvider.overrideWithValue(_FakeMdns()),
      udpBroadcastProberProvider.overrideWithValue(udp),
      fleetTransportFactoryProvider.overrideWithValue(host.transport),
      networkSnapshotProvider.overrideWithValue(
        () async => NetworkSnapshot(interfaces: interfaces, hint: null),
      ),
      followAppLifecycleProvider.overrideWithValue(false),
    ]);
  });

  tearDown(() => container.dispose());

  List<String> channelsOf(DiscoveryState s) => switch (s) {
        DiscoveryResults(:final hosts) => [
            for (final h in hosts)
              for (final c in h.channels)
                '${h.name}/${c.name}:${c.agents.map((a) => a.name).join(',')}',
          ],
        _ => const [],
      };

  test('two channels on one host are found and kept current', () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main'), _reply(29700, 'stable')];
      host.agents[29704] = ['Clamk', 'AgentY'];
      host.agents[29700] = ['Agent3'];

      expect(container.read(discoveryProvider), isA<DiscoveryScanning>());
      async.elapse(const Duration(seconds: 1));
      expect(channelsOf(container.read(discoveryProvider)), [
        'narko/local-main:AgentY,Clamk',
        'narko/stable:Agent3',
      ]);
    });
  });

  test('a channel that stops answering dims, then disappears', () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main'), _reply(29700, 'stable')];
      host.agents[29704] = ['Clamk'];
      host.agents[29700] = ['Agent3'];
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));

      // The stable channel is shut down: no more UDP replies, stream dead.
      udp.replies = [_reply(29704, 'local-main')];
      host.kill(29700);

      async.elapse(const Duration(seconds: 70));
      var s = container.read(discoveryProvider) as DiscoveryResults;
      final stable = s.hosts.single.channels.firstWhere((c) => c.name == 'stable');
      expect(stable.presence, Presence.stale);
      expect(stable.error, isNotNull);

      async.elapse(const Duration(minutes: 5));
      s = container.read(discoveryProvider) as DiscoveryResults;
      // Back to one channel, so the channel level is no longer shown.
      expect(s.hosts.single.showChannels, isFalse);
      expect(s.hosts.single.channels.single.name, 'local-main');
    });
  });

  test('a new channel appears without a refresh', () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main')];
      host.agents[29704] = ['Clamk'];
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));
      expect(channelsOf(container.read(discoveryProvider)), hasLength(1));

      udp.replies = [_reply(29704, 'local-main'), _reply(29706, 'dev')];
      host.agents[29706] = ['Korp'];
      // The next discovery round is at most 5 s away during the first minute.
      async.elapse(const Duration(seconds: 6));
      expect(channelsOf(container.read(discoveryProvider)), [
        'narko/dev:Korp',
        'narko/local-main:Clamk',
      ]);
    });
  });

  test('a network change drops what was found on the old network', () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main')];
      host.agents[29704] = ['Clamk'];
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));
      expect(container.read(discoveryProvider), isA<DiscoveryResults>());

      interfaces = ['wlan0=10.20.0.7'];
      udp.replies = [];
      async.elapse(const Duration(seconds: 6));
      expect(container.read(discoveryProvider), isA<DiscoveryEmpty>());
    });
  });

  test('a burst of sightings is one update', () {
    fakeAsync((async) {
      udp.replies = [
        for (var p = 30000; p < 30008; p++) _reply(p, 'c$p'),
      ];
      var updates = 0;
      container.listen(discoveryProvider, (_, __) => updates++);
      async.elapse(const Duration(milliseconds: 400));
      // Eight channels and their first snapshots, coalesced.
      expect(updates, lessThanOrEqualTo(2));
      expect(channelsOf(container.read(discoveryProvider)), hasLength(8));
    });
  });

  test('disposing stops every timer', () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main')];
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));
      container.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
      // tearDown disposes again; make that a no-op.
      container = ProviderContainer();
    });
  });
}
