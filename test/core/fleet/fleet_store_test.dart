import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/channel_session.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instances.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';

final t0 = DateTime(2026, 10, 3, 12);

Sighting _sight({
  String hostname = 'narko',
  String address = '192.168.1.230',
  int port = 29704,
  String authKey = 'lan-k',
  String? channel = 'local-main',
  EndpointSource source = EndpointSource.lan,
}) =>
    Sighting(
      hostname: hostname,
      address: address,
      port: port,
      authKey: authKey,
      version: '0.59.7',
      channel: channel,
      source: source,
    );

(FleetStore, String) _add(FleetStore s, Sighting sight, [DateTime? at]) {
  final (next, id, _) =
      s.sight(sight, at ?? t0, newId: () => 'r${s.records.length}');
  return (next, id);
}

void main() {
  group('FleetStore.sight', () {
    test('a new channel is added', () {
      final (s, id, effect) =
          const FleetStore().sight(_sight(), t0, newId: () => 'r0');
      expect(effect, SightingEffect.added);
      expect(s.records[id]!.channel, 'local-main');
    });

    test('two channels on one host are two records', () {
      var (s, _) = _add(const FleetStore(), _sight(port: 29704, channel: 'a'));
      (s, _) = _add(s, _sight(port: 29700, channel: 'b'));
      expect(s.records, hasLength(2));
    });

    test('the same channel seen again renews it, without a new session', () {
      var (s, id) = _add(const FleetStore(), _sight());
      final later = t0.add(const Duration(seconds: 40));
      final (s2, id2, effect) = s.sight(_sight(), later, newId: () => 'x');
      expect(id2, id);
      expect(effect, SightingEffect.renewed);
      expect(s2.records[id]!.lastSighting, later);
    });

    test('a restart on a new port relocates the same channel', () {
      var (s, id) = _add(const FleetStore(), _sight(port: 29704));
      final (s2, id2, effect) =
          s.sight(_sight(port: 29710), t0, newId: () => 'x');
      expect(id2, id);
      expect(effect, SightingEffect.relocated);
      expect(s2.records[id]!.port, 29710);
    });

    test('a different address alone keeps the working one', () {
      // narko also has VM and VPN adapters; mDNS may name any of them.
      var (s, id) = _add(const FleetStore(), _sight(address: '192.168.1.230'));
      final (s2, _, effect) =
          s.sight(_sight(address: '192.168.116.1'), t0, newId: () => 'x');
      expect(effect, SightingEffect.renewed);
      expect(s2.records[id]!.address, '192.168.1.230');
    });

    test('a different address replaces one that is failing', () {
      var (s, id) = _add(const FleetStore(), _sight(address: '192.168.116.1'));
      s = s.apply(id, const SessionFailure(ChannelError.unreachable), t0);
      final (s2, _, effect) =
          s.sight(_sight(address: '192.168.1.230'), t0, newId: () => 'x');
      expect(effect, SightingEffect.relocated);
      expect(s2.records[id]!.address, '192.168.1.230');
      expect(s2.records[id]!.error, isNull);
    });

    test('a LAN sighting never takes over a user-added connection', () {
      var (s, id) = _add(
        const FleetStore(),
        _sight(address: '10.0.2.2', authKey: 'full-k', source: EndpointSource.dev),
      );
      final (s2, _, effect) = s.sight(_sight(), t0, newId: () => 'x');
      expect(effect, SightingEffect.renewed);
      expect(s2.records[id]!.authKey, 'full-k');
      expect(s2.records[id]!.source, EndpointSource.dev);
    });

    test('an older srv without a channel name matches by port', () {
      var (s, id) = _add(const FleetStore(), _sight(channel: null));
      final (_, id2, _) =
          s.sight(_sight(channel: 'learned'), t0, newId: () => 'x');
      expect(id2, id);
    });
  });

  group('FleetStore.apply', () {
    test('a contact sets agents and clears an error', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id, const SessionFailure(ChannelError.unreachable), t0);
      s = s.apply(
        id,
        const SessionContact(agents: [LanAgent(name: 'Clamk')], epoch: 'e', rev: 1),
        t0,
      );
      expect(s.records[id]!.agents.map((a) => a.name), ['Clamk']);
      expect(s.records[id]!.error, isNull);
    });

    test('an older or repeated rev in the same epoch is ignored', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id,
          const SessionContact(agents: [LanAgent(name: 'New')], epoch: 'e', rev: 5), t0);
      s = s.apply(id,
          const SessionContact(agents: [LanAgent(name: 'Old')], epoch: 'e', rev: 4), t0);
      s = s.apply(id,
          const SessionContact(agents: [LanAgent(name: 'Dup')], epoch: 'e', rev: 5), t0);
      expect(s.records[id]!.agents.map((a) => a.name), ['New']);
      expect(s.records[id]!.rev, 5);
    });

    test('a new epoch (the srv restarted) replaces the state', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id,
          const SessionContact(agents: [LanAgent(name: 'A')], epoch: 'e1', rev: 9), t0);
      s = s.apply(id,
          const SessionContact(agents: [LanAgent(name: 'B')], epoch: 'e2', rev: 1), t0);
      expect(s.records[id]!.agents.map((a) => a.name), ['B']);
      expect(s.records[id]!.epoch, 'e2');
    });

    test('a heartbeat renews contact without touching agents', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id, const SessionContact(agents: [LanAgent(name: 'A')]), t0);
      final later = t0.add(const Duration(seconds: 15));
      s = s.apply(id, const SessionContact(), later);
      expect(s.records[id]!.agents.map((a) => a.name), ['A']);
      expect(s.records[id]!.lastContact, later);
    });

    test('a report for an unknown record is ignored', () {
      const s = FleetStore();
      expect(s.apply('nope', const SessionContact(), t0), same(s));
    });
  });

  group('presence', () {
    test('live, then stale after 60 s, then gone after 300 s', () {
      final (s, id) = _add(const FleetStore(), _sight());
      final r = s.records[id]!;
      expect(r.presence(t0.add(const Duration(seconds: 59))), Presence.live);
      expect(r.presence(t0.add(const Duration(seconds: 60))), Presence.stale);
      expect(r.presence(t0.add(const Duration(seconds: 299))), Presence.stale);
      expect(r.presence(t0.add(const Duration(seconds: 300))), Presence.gone);
    });

    test('contact and sightings both keep a channel alive', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id, const SessionContact(), t0.add(const Duration(seconds: 200)));
      expect(
        s.records[id]!.presence(t0.add(const Duration(seconds: 250))),
        Presence.live,
      );
    });

    test('a user-added channel goes stale but is never gone', () {
      final (s, id) =
          _add(const FleetStore(), _sight(source: EndpointSource.manual));
      expect(
        s.records[id]!.presence(t0.add(const Duration(hours: 5))),
        Presence.stale,
      );
    });

    test('an error is not shown while the channel is still live', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id, const SessionContact(), t0);
      s = s.apply(id, const SessionFailure(ChannelError.unreachable),
          t0.add(const Duration(seconds: 5)));
      final r = s.records[id]!;
      expect(r.visibleError(t0.add(const Duration(seconds: 10))), isNull);
      expect(r.visibleError(t0.add(const Duration(seconds: 61))),
          ChannelError.unreachable);
    });

    test('a channel still sighted but not answering shows its error', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id, const SessionContact(), t0);
      final later = t0.add(const Duration(minutes: 2));
      s = s.apply(id, const SessionFailure(ChannelError.unreachable), later);
      final (s2, _, _) = s.sight(_sight(), later, newId: () => 'x');
      final r = s2.records[id]!;
      // Discovery keeps it live, but its agents are two minutes old.
      expect(r.presence(later), Presence.live);
      expect(r.visibleError(later), ChannelError.unreachable);
    });

    test('an error on a channel never reached is shown at once', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(id, const SessionFailure(ChannelError.unauthorized), t0);
      expect(s.records[id]!.visibleError(t0), ChannelError.unauthorized);
    });
  });

  group('FleetStore.prune', () {
    test('drops gone LAN channels and reports them', () {
      var (s, lan) = _add(const FleetStore(), _sight(port: 1, channel: 'a'));
      String manual;
      (s, manual) = _add(s, _sight(port: 2, channel: 'b', source: EndpointSource.manual));
      final (pruned, gone) = s.prune(t0.add(const Duration(minutes: 10)));
      expect(gone, [lan]);
      expect(pruned.records.keys, [manual]);
    });

    test('nothing to drop returns the same store', () {
      final (s, _) = _add(const FleetStore(), _sight());
      final (pruned, gone) = s.prune(t0);
      expect(gone, isEmpty);
      expect(pruned, same(s));
    });
  });

  group('display fields', () {
    test('a sighting and a contact carry os, install id and count', () {
      var (s, id) = _add(const FleetStore(), _sight());
      final (s2, _, _) = s.sight(
        const Sighting(
          hostname: 'narko',
          address: '198.51.100.30',
          port: 29704,
          authKey: 'lan-k',
          version: '0.59.11',
          channel: 'local-main',
          os: 'windows',
          installId: 'testinstallidtestinstallid',
        ),
        t0,
        newId: () => 'x',
      );
      s = s2.apply(
        id,
        const SessionContact(epoch: 'e', rev: 1, channelsRunning: 3),
        t0,
      );
      final i = s.records[id]!.toInstance();
      expect(i.os, 'windows');
      expect(i.installId, 'testinstallidtestinstallid');
      expect(i.channelsRunning, 3);
    });

    test('a stale rev does not change the channel count', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(
          id, const SessionContact(epoch: 'e', rev: 5, channelsRunning: 3), t0);
      s = s.apply(
          id, const SessionContact(epoch: 'e', rev: 4, channelsRunning: 1), t0);
      expect(s.records[id]!.channelsRunning, 3);
    });
  });

  group('route', () {
    test('LAN discovery is LAN; a QR/manual entry is LAN only when private',
        () {
      final (s, lan) = _add(const FleetStore(), _sight());
      expect(s.records[lan]!.route, ChannelRoute.lan);
      final (s2, private) = _add(
        s,
        _sight(port: 2, channel: 'b', source: EndpointSource.manual),
      );
      expect(s2.records[private]!.route, ChannelRoute.lan);
      final (s3, public) = _add(
        s2,
        _sight(
          hostname: 'far',
          address: '203.0.113.7',
          port: 3,
          channel: 'c',
          source: EndpointSource.manual,
        ),
      );
      expect(s3.records[public]!.route, ChannelRoute.direct);
    });
  });

  group('cloud channels', () {
    CloudInstance cloud(
      String id, {
      String hostname = 'atlas',
      String channel = 'stable',
      DateTime? receivedAt,
    }) =>
        CloudInstance(
          instanceId: id,
          hostname: hostname,
          channel: channel,
          version: '0.59.11',
          os: 'macos',
          channelsRunning: 2,
          agents: const [LanAgent(name: 'AgentA', kind: AgentKind.host)],
          receivedAtMs: (receivedAt ?? t0).millisecondsSinceEpoch,
        );

    test('each install becomes one cloud record, keyed by its id', () {
      final s = const FleetStore().syncCloud([cloud('aaaa'), cloud('bbbb')]);
      final r = s.records[FleetStore.cloudRecordId('aaaa')]!;
      expect(r.source, EndpointSource.cloud);
      expect(r.route, ChannelRoute.cloud);
      expect(r.installId, 'aaaa');
      expect(r.os, 'macos');
      expect(r.agents.single.kind, AgentKind.host);
      expect(s.records, hasLength(2));
    });

    test('a refresh replaces the cloud records and leaves LAN ones alone', () {
      var (s, lan) = _add(const FleetStore(), _sight());
      s = s.syncCloud([cloud('aaaa'), cloud('bbbb')]);
      s = s.syncCloud([cloud('bbbb')]);
      expect(s.records.keys,
          unorderedEquals([lan, FleetStore.cloudRecordId('bbbb')]));
      s = s.clearCloud();
      expect(s.records.keys, [lan]);
    });

    test('live while received in the last 3 minutes, then stale, never gone',
        () {
      final s = const FleetStore().syncCloud([cloud('aaaa')]);
      final r = s.records[FleetStore.cloudRecordId('aaaa')]!;
      expect(r.presence(t0.add(const Duration(minutes: 2))), Presence.live);
      expect(r.presence(t0.add(const Duration(minutes: 3))), Presence.stale);
      expect(r.presence(t0.add(const Duration(hours: 20))), Presence.stale);
      final (pruned, gone) = s.prune(t0.add(const Duration(hours: 20)));
      expect(gone, isEmpty);
      expect(pruned.records, hasLength(1));
    });

    test('a LAN sighting never lands on a cloud record of the same name', () {
      var s = const FleetStore()
          .syncCloud([cloud('aaaa', hostname: 'narko', channel: 'local-main')]);
      final (s2, id, effect) = s.sight(_sight(), t0, newId: () => 'lan0');
      expect(effect, SightingEffect.added);
      expect(id, 'lan0');
      expect(s2.records, hasLength(2));
    });
  });

  group('agent states', () {
    final since = StateSince(
      elapsedAtReceipt: const Duration(minutes: 3),
      receivedAt: t0,
    );

    test('a contact carries states; a stale rev does not change them', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(
        id,
        SessionContact(
          agents: [
            LanAgent(
              name: 'A',
              state: AgentState.working,
              stateSince: since,
            ),
          ],
          epoch: 'e',
          rev: 5,
        ),
        t0,
      );
      s = s.apply(
        id,
        const SessionContact(
          agents: [LanAgent(name: 'A', state: AgentState.idle)],
          epoch: 'e',
          rev: 4,
        ),
        t0,
      );
      final a = s.records[id]!.toInstance().agents.single;
      expect(a.state, AgentState.working);
      expect(a.stateSince, since);
    });

    test('a newer rev replaces the state', () {
      var (s, id) = _add(const FleetStore(), _sight());
      s = s.apply(
        id,
        const SessionContact(
          agents: [LanAgent(name: 'A', state: AgentState.working)],
          epoch: 'e',
          rev: 1,
        ),
        t0,
      );
      s = s.apply(
        id,
        const SessionContact(
          agents: [LanAgent(name: 'A', state: AgentState.idle)],
          epoch: 'e',
          rev: 2,
        ),
        t0,
      );
      expect(s.records[id]!.agents.single.state, AgentState.idle);
    });

    test('a cloud record keeps its agents\' states', () {
      final asOf = DateTime.fromMillisecondsSinceEpoch(
          t0.millisecondsSinceEpoch);
      final s = const FleetStore().syncCloud([
        CloudInstance(
          instanceId: 'aaaa',
          hostname: 'atlas',
          channel: 'stable',
          version: '0.59.11',
          agents: [
            LanAgent(name: 'A', state: AgentState.waiting, stateAsOf: asOf),
          ],
          receivedAtMs: t0.millisecondsSinceEpoch,
        ),
      ]);
      final a = s.records[FleetStore.cloudRecordId('aaaa')]!.agents.single;
      expect(a.state, AgentState.waiting);
      expect(a.stateAsOf, asOf);
    });
  });
}
