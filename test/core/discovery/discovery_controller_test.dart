import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';
import 'package:agentmux_mobile/core/discovery/mdns_scanner.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/discovery/network_environment.dart';
import 'package:agentmux_mobile/core/discovery/udp_broadcast_prober.dart';
import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instance_source.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instances.dart';
import 'package:agentmux_mobile/core/fleet/fleet_snapshot.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/core/fleet/fleet_transport.dart';
import 'package:agentmux_mobile/core/discovery/lan_scanner.dart';
import 'package:agentmux_mobile/core/fleet/channel_session.dart';
import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/paired_host_source.dart';
import 'package:agentmux_mobile/core/viewer/paired_hosts_repository.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:flutter/foundation.dart';

import '../viewer/viewer_fakes.dart';

class _FakeMdns extends MdnsScanner {
  var scans = 0;

  @override
  Stream<LanInstance> scan({bool logSummary = true}) {
    scans++;
    return const Stream.empty();
  }
}

class _FakeUdp extends UdpBroadcastProber {
  List<LanInstance> replies = [];
  var probes = 0;

  @override
  Stream<LanInstance> probe({
    Duration timeout = const Duration(seconds: 2),
    bool tryEmulatorRelay = false,
    bool logSummary = true,
  }) {
    probes++;
    return Stream.fromIterable(replies);
  }
}

/// One fake desktop channel per port: streams its agents while alive.
class _FakeHost {
  /// The hostname every channel reports.
  var hostname = 'narko';
  final agents = <int, List<String>>{};
  final connects = <int, int>{};
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
    host.connects.update(port, (n) => n + 1, ifAbsent: () => 1);
    if (host.dead.contains(port)) return Stream.error(_down);
    final c = StreamController<FleetSnapshot?>();
    host.open.putIfAbsent(port, () => []).add(c);
    c
      ..add(null)
      ..add(FleetSnapshot(
        epoch: 'e$port',
        rev: 1,
        hostname: host.hostname,
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

LanInstance _reply(int port, String channel, {String hostname = 'narko'}) =>
    LanInstance(
      hostname: hostname,
      version: '0.59.7',
      address: '192.168.1.230',
      port: port,
      authKey: 'lan-$port',
      channel: channel,
    );

/// A Bonjour browse that finds a fixed set of instances.
class _FakeBonjour implements LanScanner {
  List<LanInstance> found = [];
  var scans = 0;

  @override
  Stream<LanInstance> scan({bool logSummary = true}) {
    scans++;
    return Stream.fromIterable(found);
  }
}

/// Paired computers' viewer listeners: each read answers [answer], or throws
/// [failure] when set.
class _FakePaired {
  final fetches = <String>[];
  Object? failure;
  PairedSnapshot Function(PairedHost host) answer = (_) => _snapshot();

  Future<PairedSnapshot> fetch(PairedHost host) async {
    fetches.add(host.id);
    final f = failure;
    if (f != null) throw f;
    return answer(host);
  }
}

PairedSnapshot _snapshot({
  String hostname = 'host-a',
  String? channel = 'stable',
  List<LanAgent> agents = const [
    LanAgent(name: 'AgentA', kind: AgentKind.host, state: AgentState.working),
    LanAgent(name: 'AgentB', kind: AgentKind.container, state: AgentState.idle),
  ],
}) =>
    PairedSnapshot(
      hello: ViewerHello(
        hostname: hostname,
        deviceId: 'dev-1',
        channel: channel,
        version: '0.60.0',
        installId: testInstallId,
      ),
      agents: agents,
    );

/// The account's install list as the fake relay serves it.
class _FakeCloud {
  var signedIn = false;
  var fetches = 0;
  Object? failure;
  List<CloudInstance> Function() list = () => const [];

  Future<bool> isSignedIn() async => signedIn;

  Future<List<CloudInstance>> fetch() async {
    fetches++;
    final f = failure;
    if (f != null) throw f;
    return list();
  }
}

CloudInstance _install(
  String id, {
  String hostname = 'atlas',
  String channel = 'stable',
  required DateTime receivedAt,
  bool gone = false,
}) =>
    CloudInstance(
      instanceId: id,
      hostname: hostname,
      channel: channel,
      version: '0.59.11',
      os: 'macos',
      agents: const [LanAgent(name: 'AgentA', kind: AgentKind.host)],
      receivedAtMs: receivedAt.millisecondsSinceEpoch,
      gone: gone,
      goneAtMs: gone ? receivedAt.millisecondsSinceEpoch : null,
    );

void main() {
  late _FakeUdp udp;
  late _FakeHost host;
  late _FakeCloud cloud;
  late List<String> interfaces;
  late ProviderContainer container;

  setUp(() {
    udp = _FakeUdp();
    host = _FakeHost();
    cloud = _FakeCloud();
    interfaces = ['wlan0=192.168.1.50'];
    container = ProviderContainer(overrides: [
      cloudSignedInProvider.overrideWithValue(cloud.isSignedIn),
      cloudInstancesFetchProvider.overrideWithValue(cloud.fetch),
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

  test('a network change reconnects without blanking the screen', () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main')];
      host.agents[29704] = ['Clamk'];
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));
      expect(host.connects[29704], 1);

      // A different Wi-Fi network; the old host is not on it.
      interfaces = ['wlan0=10.20.0.7'];
      udp.replies = [];
      host.kill(29704);
      async.elapse(const Duration(seconds: 6));
      expect(host.connects[29704], greaterThan(1), reason: 'reconnected');
      expect(container.read(discoveryProvider), isA<DiscoveryResults>(),
          reason: 'still shown, dimming, not wiped');

      // It ages out like any other quiet channel.
      async.elapse(const Duration(minutes: 6));
      expect(container.read(discoveryProvider), isA<DiscoveryEmpty>());
    });
  });

  test('IPv6, mobile data and a failed enumeration are not a network change',
      () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main')];
      host.agents[29704] = ['Clamk'];
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));
      expect(host.connects[29704], 1);

      interfaces = [
        'wlan0=192.168.1.50',
        'wlan0=fe80::1c2b:3aff:fe4d:5e6f',
        'rmnet_data0=10.71.4.2',
      ];
      async.elapse(const Duration(seconds: 6));
      interfaces = [];
      async.elapse(const Duration(seconds: 6));
      interfaces = ['wlan0=192.168.1.50'];
      async.elapse(const Duration(seconds: 6));
      expect(host.connects[29704], 1, reason: 'the stream was never dropped');
    });
  });

  test('channels that went quiet in the background stay visible on resume',
      () {
    fakeAsync((async) {
      udp.replies = [_reply(29704, 'local-main')];
      host.agents[29704] = ['Clamk'];
      final notifier = container.read(discoveryProvider.notifier);
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));

      notifier.handlePause();
      async.elapse(const Duration(minutes: 10));
      notifier.handleResume();
      async.elapse(const Duration(milliseconds: 200));
      // Long past the 300 s limit, yet shown (dimmed) while it reconnects.
      final s = container.read(discoveryProvider);
      expect(s, isA<DiscoveryResults>());
      async.elapse(const Duration(seconds: 2));
      final after = container.read(discoveryProvider) as DiscoveryResults;
      expect(after.hosts.single.presence, Presence.live);
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

  group('cloud hosts', () {
    List<ChannelNode> channels(DiscoveryState s) => switch (s) {
          DiscoveryResults(:final hosts) => [
              for (final h in hosts) ...h.channels,
            ],
          _ => const [],
        };

    test('signed out: nothing is fetched and the note says so', () {
      fakeAsync((async) {
        udp.replies = [_reply(29704, 'local-main')];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        expect(cloud.fetches, 0);
        final s = container.read(discoveryProvider) as DiscoveryResults;
        expect(s.cloud, CloudListStatus.signedOut);
      });
    });

    test('signed out with nothing on the LAN: the empty view carries the note',
        () {
      fakeAsync((async) {
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 3));
        final s = container.read(discoveryProvider) as DiscoveryEmpty;
        expect(s.cloud, CloudListStatus.signedOut);
      });
    });

    test('signed in: a cloud-only install shows as a cloud channel', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        final t0 = DateTime.now();
        cloud.list = () => [_install('aaaa', receivedAt: t0)];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        final s = container.read(discoveryProvider) as DiscoveryResults;
        expect(s.cloud, CloudListStatus.ok);
        final atlas = s.hosts.single;
        expect(atlas.name, 'atlas');
        expect(atlas.platform, HostPlatform.macos);
        expect(atlas.route, ChannelRoute.cloud);
        expect(atlas.channels.single.cloudOnly, isTrue);
        expect(atlas.channels.single.agents.single.kind, AgentKind.host);
      });
    });

    test('presence follows received_at_ms: live under 3 min, then dimmed', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        // The install stopped publishing: the relay keeps returning the
        // same record with the same receive time.
        final received = DateTime.now();
        cloud.list = () => [_install('aaaa', receivedAt: received)];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        expect(channels(container.read(discoveryProvider)).single.presence,
            Presence.live);
        async.elapse(const Duration(minutes: 3));
        final c = channels(container.read(discoveryProvider)).single;
        expect(c.presence, Presence.stale);
        // Still shown long after: only the relay dropping it hides it.
        async.elapse(const Duration(minutes: 20));
        expect(channels(container.read(discoveryProvider)), hasLength(1));
        cloud.list = () => const [];
        async.elapse(const Duration(seconds: 31));
        expect(container.read(discoveryProvider), isA<DiscoveryEmpty>());
      });
    });

    test('a LAN channel and its cloud record merge by install id', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        cloud.list = () => [
              _install(
                'testinstallidtestinstallid',
                hostname: 'narko',
                channel: 'local-main',
                receivedAt: DateTime.now(),
              ),
            ];
        udp.replies = [
          _reply(29704, 'local-main')
              .copyWith(installId: 'testinstallidtestinstallid'),
        ];
        host.agents[29704] = ['Clamk'];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        final c = channels(container.read(discoveryProvider)).single;
        expect(c.route, ChannelRoute.lanAndCloud);
        expect(c.via.port, 29704);
        expect(c.agents.map((a) => a.name), ['Clamk']);
      });
    });

    test('a signed-off install disappears at the next read, not 3 min later',
        () {
      fakeAsync((async) {
        cloud.signedIn = true;
        cloud.list = () => [_install('aaaa', receivedAt: DateTime.now())];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        expect(channels(container.read(discoveryProvider)).single.presence,
            Presence.live);
        // The desktop quit and said goodbye; the relay lists a tombstone.
        cloud.list = () =>
            [_install('aaaa', receivedAt: DateTime.now(), gone: true)];
        async.elapse(const Duration(seconds: 31));
        expect(container.read(discoveryProvider), isA<DiscoveryEmpty>());
      });
    });

    test('a tombstone leaves the same install on the LAN as a LAN channel',
        () {
      fakeAsync((async) {
        cloud.signedIn = true;
        // Signed out of the cloud, still running on this network.
        cloud.list = () => [
              _install(
                'testinstallidtestinstallid',
                hostname: 'narko',
                channel: 'local-main',
                receivedAt: DateTime.now(),
                gone: true,
              ),
            ];
        udp.replies = [
          _reply(29704, 'local-main')
              .copyWith(installId: 'testinstallidtestinstallid'),
        ];
        host.agents[29704] = ['Clamk'];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        final c = channels(container.read(discoveryProvider)).single;
        expect(c.route, ChannelRoute.lan);
        expect(c.presence, Presence.live);
        expect(c.notPublishingSince, isNull);
      });
    });

    test('on the LAN but its cloud record stale: not publishing since then',
        () {
      fakeAsync((async) {
        cloud.signedIn = true;
        final received = DateTime.now().subtract(const Duration(minutes: 5));
        cloud.list = () => [
              _install(
                'testinstallidtestinstallid',
                hostname: 'narko',
                channel: 'local-main',
                receivedAt: received,
              ),
            ];
        udp.replies = [
          _reply(29704, 'local-main')
              .copyWith(installId: 'testinstallidtestinstallid'),
        ];
        host.agents[29704] = ['Clamk'];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        var c = channels(container.read(discoveryProvider)).single;
        expect(c.route, ChannelRoute.lan);
        expect(c.notPublishingSince?.millisecondsSinceEpoch,
            received.millisecondsSinceEpoch);
        // A list this device cannot read says nothing about the install.
        cloud.failure = DioException(
          requestOptions: RequestOptions(path: '/wan-instances'),
          type: DioExceptionType.connectionError,
        );
        async.elapse(const Duration(seconds: 31));
        c = channels(container.read(discoveryProvider)).single;
        expect(c.notPublishingSince, isNull);
      });
    });

    test('a failed list keeps what was shown and says unavailable', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        cloud.list = () => [_install('aaaa', receivedAt: DateTime.now())];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        cloud.failure = DioException(
          requestOptions: RequestOptions(path: '/wan-instances'),
          type: DioExceptionType.connectionError,
        );
        async.elapse(const Duration(seconds: 31));
        final s = container.read(discoveryProvider) as DiscoveryResults;
        expect(s.cloud, CloudListStatus.unavailable);
        expect(channels(s), hasLength(1));
      });
    });

    test('an older relay (404) is not a note', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        cloud.failure = const CloudInstancesUnsupported();
        udp.replies = [_reply(29704, 'local-main')];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        final s = container.read(discoveryProvider) as DiscoveryResults;
        expect(s.cloud, CloudListStatus.unsupported);
      });
    });

    test('signing out removes cloud channels', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        cloud.list = () => [_install('aaaa', receivedAt: DateTime.now())];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        cloud.signedIn = false;
        container.read(discoveryProvider.notifier).refreshCloud();
        async.elapse(const Duration(seconds: 1));
        expect(container.read(discoveryProvider), isA<DiscoveryEmpty>());
      });
    });

    test('the cloud list stops in the background and resumes in front', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        final notifier = container.read(discoveryProvider.notifier);
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        expect(cloud.fetches, 1);
        notifier.handlePause();
        async.elapse(const Duration(minutes: 5));
        expect(cloud.fetches, 1);
        notifier.handleResume();
        async.elapse(const Duration(seconds: 1));
        expect(cloud.fetches, 2);
      });
    });

    test('pull-to-refresh asks the cloud too', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        final notifier = container.read(discoveryProvider.notifier);
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        notifier.refresh();
        async.elapse(const Duration(seconds: 3));
        expect(cloud.fetches, 2);
      });
    });
  });

  group('paired hosts', () {
    late InMemorySecureStore store;
    late _FakePaired paired;

    setUp(() {
      store = InMemorySecureStore();
      paired = _FakePaired();
      // The fake channels report the paired host's name.
      host.hostname = 'host-a';
      container.dispose();
      container = ProviderContainer(overrides: [
        pairedHostFetchProvider.overrideWithValue(paired.fetch),
        cloudSignedInProvider.overrideWithValue(cloud.isSignedIn),
        cloudInstancesFetchProvider.overrideWithValue(cloud.fetch),
        mdnsScannerProvider.overrideWithValue(_FakeMdns()),
        udpBroadcastProberProvider.overrideWithValue(udp),
        fleetTransportFactoryProvider.overrideWithValue(host.transport),
        networkSnapshotProvider.overrideWithValue(
          () async => NetworkSnapshot(interfaces: interfaces, hint: null),
        ),
        followAppLifecycleProvider.overrideWithValue(false),
        secureStoreProvider.overrideWithValue(store),
      ]);
    });

    LanInstance reply({int? viewerPort}) => LanInstance(
          hostname: 'host-a',
          version: '0.60.0',
          address: '198.51.100.44',
          port: 29704,
          authKey: 'lan-k',
          channel: 'stable',
          installId: testInstallId,
          viewerPort: viewerPort,
        );

    test('a discovered channel carries its pairing, at its new address', () {
      fakeAsync((async) {
        PairedHostsRepository(store).save([testPairedHost()]);
        async.flushMicrotasks();
        udp.replies = [reply(viewerPort: 29811)];
        host.agents[29704] = ['AgentA'];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));

        final s = container.read(discoveryProvider) as DiscoveryResults;
        final m = s.hosts.single.channels.single.pairing!;
        expect(m.paired.id, 'p1');
        expect((m.host, m.port), ('198.51.100.44', 29811));
        // The move is stored, once.
        async.elapse(const Duration(seconds: 1));
        final stored = container.read(pairedHostsProvider).single;
        expect((stored.host, stored.port), ('198.51.100.44', 29811));
        final writes = store.writes;
        async.elapse(const Duration(seconds: 30));
        expect(store.writes, writes);
      });
    });

    test('unpairing takes the pairing off the channel', () {
      fakeAsync((async) {
        PairedHostsRepository(store).save([testPairedHost()]);
        async.flushMicrotasks();
        udp.replies = [reply()];
        host.agents[29704] = ['AgentA'];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        container.read(pairedHostsProvider.notifier).remove('p1');
        async.elapse(const Duration(seconds: 1));
        final s = container.read(discoveryProvider) as DiscoveryResults;
        expect(s.hosts.single.channels.single.pairing, isNull);
      });
    });

    test('discovery finding the paired channel stops reading it directly', () {
      fakeAsync((async) {
        PairedHostsRepository(store).save([testPairedHost()]);
        async.flushMicrotasks();
        udp.replies = [reply()];
        host.agents[29704] = ['AgentA'];
        container.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));
        final reads = paired.fetches.length;
        async.elapse(const Duration(seconds: 60));
        expect(paired.fetches.length, reads);
      });
    });
  });

  group('platform', () {
    late _FakeMdns mdns;
    late _FakeBonjour bonjour;

    ProviderContainer on(TargetPlatform platform) => ProviderContainer(
          overrides: [
            discoveryPlatformProvider.overrideWithValue(platform),
            bonjourScannerProvider.overrideWithValue(bonjour),
            cloudSignedInProvider.overrideWithValue(cloud.isSignedIn),
            cloudInstancesFetchProvider.overrideWithValue(cloud.fetch),
            mdnsScannerProvider.overrideWithValue(mdns),
            udpBroadcastProberProvider.overrideWithValue(udp),
            fleetTransportFactoryProvider.overrideWithValue(host.transport),
            networkSnapshotProvider.overrideWithValue(
              () async => NetworkSnapshot(interfaces: interfaces, hint: null),
            ),
            followAppLifecycleProvider.overrideWithValue(false),
          ],
        );

    setUp(() {
      mdns = _FakeMdns();
      bonjour = _FakeBonjour();
    });

    test('iOS finds channels through Bonjour and sends no UDP probe', () {
      fakeAsync((async) {
        final c = on(TargetPlatform.iOS);
        addTearDown(c.dispose);
        host.hostname = 'host-a';
        bonjour.found = [_reply(29704, 'local-main', hostname: 'host-a')];
        host.agents[29704] = ['AgentA'];
        c.read(discoveryProvider);
        async.elapse(const Duration(seconds: 12));

        expect(channelsOf(c.read(discoveryProvider)),
            ['host-a/local-main:AgentA']);
        expect(bonjour.scans, greaterThan(1));
        expect(mdns.scans, 0);
        expect(udp.probes, 0);
      });
    });

    test('Android keeps multicast_dns and the UDP probe', () {
      fakeAsync((async) {
        final c = on(TargetPlatform.android);
        addTearDown(c.dispose);
        host.hostname = 'host-a';
        udp.replies = [_reply(29704, 'local-main', hostname: 'host-a')];
        host.agents[29704] = ['AgentA'];
        c.read(discoveryProvider);
        async.elapse(const Duration(seconds: 1));

        expect(channelsOf(c.read(discoveryProvider)),
            ['host-a/local-main:AgentA']);
        expect(mdns.scans, 1);
        expect(udp.probes, 1);
        expect(bonjour.scans, 0);
      });
    });
  });

  group('paired computers discovery has not found', () {
    late InMemorySecureStore store;
    late _FakePaired paired;

    setUp(() {
      store = InMemorySecureStore();
      paired = _FakePaired();
      // The fake channels report the paired host's name.
      host.hostname = 'host-a';
      container.dispose();
      container = ProviderContainer(overrides: [
        pairedHostFetchProvider.overrideWithValue(paired.fetch),
        cloudSignedInProvider.overrideWithValue(cloud.isSignedIn),
        cloudInstancesFetchProvider.overrideWithValue(cloud.fetch),
        mdnsScannerProvider.overrideWithValue(_FakeMdns()),
        udpBroadcastProberProvider.overrideWithValue(udp),
        fleetTransportFactoryProvider.overrideWithValue(host.transport),
        networkSnapshotProvider.overrideWithValue(
          () async => NetworkSnapshot(interfaces: interfaces, hint: null),
        ),
        followAppLifecycleProvider.overrideWithValue(false),
        secureStoreProvider.overrideWithValue(store),
      ]);
    });

    /// Starts discovery with [hosts] already paired.
    void start(FakeAsync async, [List<PairedHost>? hosts]) {
      PairedHostsRepository(store).save(hosts ?? [testPairedHost()]);
      async.flushMicrotasks();
      container.read(discoveryProvider);
      async.elapse(const Duration(seconds: 1));
    }

    ChannelNode only() {
      final s = container.read(discoveryProvider) as DiscoveryResults;
      return s.hosts.single.channels.single;
    }

    test('shows as a host card with its agents, kinds and states', () {
      fakeAsync((async) {
        start(async);
        final s = container.read(discoveryProvider) as DiscoveryResults;
        final h = s.hosts.single;
        final c = h.channels.single;
        expect(h.name, 'host-a');
        expect(h.version, '0.60.0');
        expect(h.route, ChannelRoute.lan);
        expect(c.name, 'stable');
        expect(c.presence, Presence.live);
        expect(c.pairedId, 'p1');
        expect(c.pairing!.paired.id, 'p1');
        // The pairing's own listener, as stored.
        expect((c.pairing!.host, c.pairing!.port), ('198.51.100.20', 29800));
        expect(
          [for (final a in c.agents) (a.name, a.kind, a.state)],
          [
            ('AgentA', AgentKind.host, AgentState.working),
            ('AgentB', AgentKind.container, AgentState.idle),
          ],
        );
        expect(paired.fetches, ['p1']);
      });
    });

    test('is read again every 10 s', () {
      fakeAsync((async) {
        start(async);
        expect(paired.fetches, hasLength(1));
        async.elapse(const Duration(seconds: 10));
        expect(paired.fetches, hasLength(2));
        async.elapse(const Duration(seconds: 20));
        expect(paired.fetches, hasLength(4));
      });
    });

    test('a failed read dims it and keeps what was known', () {
      fakeAsync((async) {
        start(async);
        paired.failure = DioException(
          requestOptions: RequestOptions(path: '/agentmux/viewer/hello'),
          type: DioExceptionType.connectionTimeout,
        );
        async.elapse(const Duration(seconds: 10));
        final c = only();
        expect(c.presence, Presence.stale);
        expect(c.error, ChannelError.unreachable);
        expect(c.agents.map((a) => a.name), ['AgentA', 'AgentB']);

        // It answers again: live.
        paired.failure = null;
        async.elapse(const Duration(seconds: 10));
        expect(only().presence, Presence.live);
        expect(only().error, isNull);
      });
    });

    test('never answering, it still shows, dimmed', () {
      fakeAsync((async) {
        paired.failure = const SocketException('unreachable');
        start(async);
        final c = only();
        expect(c.presence, Presence.stale);
        expect(c.error, ChannelError.unreachable);
        expect(c.pairing!.paired.id, 'p1');
      });
    });

    test('a 401 marks the pairing invalid and stops reading it', () {
      fakeAsync((async) {
        paired.failure = const ViewerUnauthorized();
        start(async);
        expect(container.read(pairedHostsProvider).single.invalid, isTrue);
        final c = only();
        expect(c.pairing!.paired.invalid, isTrue);
        expect(c.error, ChannelError.unauthorized);
        final reads = paired.fetches.length;
        async.elapse(const Duration(seconds: 60));
        expect(paired.fetches, hasLength(reads));
      });
    });

    test('a pairing already refused shows without being read', () {
      fakeAsync((async) {
        start(async, [testPairedHost(invalid: true)]);
        expect(only().pairing!.paired.invalid, isTrue);
        expect(paired.fetches, isEmpty);
      });
    });

    test('found by discovery later (install id), it merges into one card', () {
      fakeAsync((async) {
        start(async);
        expect(only().pairedId, 'p1');

        // Discovery finds the same install, under another address.
        udp.replies = [
          const LanInstance(
            hostname: 'host-a',
            version: '0.60.0',
            address: '198.51.100.44',
            port: 29704,
            authKey: 'lan-k',
            channel: 'stable',
            installId: testInstallId,
          ),
        ];
        host.agents[29704] = ['AgentA'];
        async.elapse(const Duration(seconds: 6));

        final c = only();
        expect(c.pairedId, isNull);
        expect(c.pairing!.paired.id, 'p1');
        expect(c.via.port, 29704);
        // No longer read directly.
        final reads = paired.fetches.length;
        async.elapse(const Duration(seconds: 30));
        expect(paired.fetches, hasLength(reads));
      });
    });

    test('found by discovery by hostname and channel when no install id', () {
      fakeAsync((async) {
        start(async, [testPairedHost(installId: null)]);
        udp.replies = [
          const LanInstance(
            hostname: 'HOST-A',
            version: '0.60.0',
            address: '198.51.100.44',
            port: 29704,
            authKey: 'lan-k',
            channel: 'stable',
          ),
        ];
        host.agents[29704] = ['AgentA'];
        async.elapse(const Duration(seconds: 6));
        final c = only();
        expect(c.pairedId, isNull);
        expect(c.pairing!.paired.id, 'p1');
      });
    });

    test('next to a discovered channel of the same host, it is its own', () {
      fakeAsync((async) {
        udp.replies = [_reply(29704, 'local-main', hostname: 'host-a')];
        host.agents[29704] = ['AgentC'];
        start(async, [testPairedHost(installId: null)]);
        async.elapse(const Duration(seconds: 10));
        expect(channelsOf(container.read(discoveryProvider)), [
          'host-a/local-main:AgentC',
          'host-a/stable:AgentA,AgentB',
        ]);
      });
    });

    test('reading stops in the background and resumes in front', () {
      fakeAsync((async) {
        start(async);
        final notifier = container.read(discoveryProvider.notifier);
        notifier.handlePause();
        final reads = paired.fetches.length;
        async.elapse(const Duration(minutes: 2));
        expect(paired.fetches, hasLength(reads));

        notifier.handleResume();
        async.elapse(const Duration(seconds: 1));
        expect(paired.fetches, hasLength(reads + 1));
      });
    });

    test('pull-to-refresh reads it at once', () {
      fakeAsync((async) {
        start(async);
        container.read(discoveryProvider.notifier).refresh();
        async.elapse(const Duration(milliseconds: 10));
        expect(paired.fetches, hasLength(2));
      });
    });

    test('unpairing removes the card', () {
      fakeAsync((async) {
        start(async);
        container.read(pairedHostsProvider.notifier).remove('p1');
        async.elapse(const Duration(seconds: 6));
        expect(container.read(discoveryProvider), isA<DiscoveryEmpty>());
      });
    });

    test('off the LAN, an install in the cloud list keeps its cloud card', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        cloud.list = () => [_install(testInstallId, hostname: 'host-a',
            receivedAt: DateTime.now())];
        paired.failure = const SocketException('unreachable');
        start(async);
        final c = only();
        expect(c.cloudOnly, isTrue);
        expect(c.pairedId, isNull);
      });
    });

    test('on the LAN, it joins the cloud card of its install', () {
      fakeAsync((async) {
        cloud.signedIn = true;
        cloud.list = () => [_install(testInstallId, hostname: 'host-a',
            receivedAt: DateTime.now())];
        start(async);
        final c = only();
        expect(c.cloudOnly, isFalse);
        expect(c.pairedId, 'p1');
        expect(c.route, ChannelRoute.lanAndCloud);
      });
    });
  });
}
