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
import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instance_source.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instances.dart';
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
  String hostname = 'area54',
  String channel = 'stable',
  required DateTime receivedAt,
}) =>
    CloudInstance(
      instanceId: id,
      hostname: hostname,
      channel: channel,
      version: '0.59.11',
      os: 'macos',
      agents: const [LanAgent(name: 'AgentA', kind: AgentKind.host)],
      receivedAtMs: receivedAt.millisecondsSinceEpoch,
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
        final area54 = s.hosts.single;
        expect(area54.name, 'area54');
        expect(area54.platform, HostPlatform.macos);
        expect(area54.route, ChannelRoute.cloud);
        expect(area54.channels.single.cloudOnly, isTrue);
        expect(area54.channels.single.agents.single.kind, AgentKind.host);
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
                'mw3am46w5weex4a4fqrc3avnua',
                hostname: 'narko',
                channel: 'local-main',
                receivedAt: DateTime.now(),
              ),
            ];
        udp.replies = [
          _reply(29704, 'local-main')
              .copyWith(installId: 'mw3am46w5weex4a4fqrc3avnua'),
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
}
