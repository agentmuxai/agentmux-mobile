import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/channel_session.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/paired_host_source.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewer_fakes.dart';

const _hello = {
  'hostname': 'host-a',
  'device_id': 'dev-1',
  'channel': 'stable',
  'version': '0.60.0',
  'install_id': testInstallId,
};

const _agents = {
  'now_ms': 1000000,
  'agents': [
    {'name': 'AgentA', 'kind': 'host', 'state': 'working', 'since_ms': 820000},
    {'name': 'AgentB', 'kind': 'container', 'state': 'idle'},
    {'name': 'AgentC', 'state': 'something-new'},
  ],
};

PairedSnapshot _snapshot() => const PairedSnapshot(
      hello: ViewerHello(
        hostname: 'host-a',
        deviceId: 'dev-1',
        channel: 'stable',
        version: '0.60.0',
      ),
      agents: [LanAgent(name: 'AgentA', kind: AgentKind.host)],
    );

void main() {
  group('viewerPairedFetch', () {
    late FakeAdapter adapter;
    final clients = <ViewerClient>[];

    PairedFetch fetchWith(List<FakeResponse> script) {
      adapter = FakeAdapter(script);
      return viewerPairedFetch(
        ({required host, required port, required fingerprint, token}) {
          final c = ViewerClient(
            host: host,
            port: port,
            fingerprint: fingerprint,
            token: token,
            adapter: adapter,
          );
          clients.add(c);
          return c;
        },
      );
    }

    test('reads hello, then agents, over the stored pinned endpoint',
        () async {
      final receivedAt = DateTime.utc(2026, 10, 8, 12);
      final fetch = fetchWith(const [
        FakeResponse(200, json: _hello),
        FakeResponse(200, json: _agents),
      ]);
      final snap =
          await withClock(Clock.fixed(receivedAt), () => fetch(testPairedHost()));

      expect(adapter.requests.map((r) => r.uri.toString()), [
        'https://198.51.100.20:29800/agentmux/viewer/hello',
        'https://198.51.100.20:29800/agentmux/viewer/agents',
      ]);
      expect(adapter.requests.first.headers['Authorization'],
          'Bearer amxv_testtoken');
      expect(snap.hello.hostname, 'host-a');
      expect(snap.hello.channel, 'stable');
      expect(snap.hello.version, '0.60.0');

      final a = snap.agents;
      expect([for (final x in a) (x.name, x.kind, x.state)], [
        ('AgentA', AgentKind.host, AgentState.working),
        ('AgentB', AgentKind.container, AgentState.idle),
        // An unknown state is no state, never a guess.
        ('AgentC', null, null),
      ]);
      // The desktop's own now_ms - since_ms, anchored at this device's clock.
      expect(
        a.first.stateSince,
        StateSince(
          elapsedAtReceipt: const Duration(minutes: 3),
          receivedAt: receivedAt,
        ),
      );
      expect(a[1].stateSince, isNull);
    });

    test('a 401 is ViewerUnauthorized', () async {
      final fetch = fetchWith(const [FakeResponse(401)]);
      await expectLater(
        fetch(testPairedHost()),
        throwsA(isA<ViewerUnauthorized>()),
      );
    });
  });

  group('pairedFleetEntry', () {
    final now = DateTime.utc(2026, 10, 8, 12);

    test('nothing until the first read, so a card never appears empty', () {
      expect(pairedFleetEntry(testPairedHost(), null, now), isNull);
    });

    test('a read: the hello names it, the agents fill it, route LAN', () {
      final reading = const PairedReading()
          .after(PairedPollOk(_snapshot()), now);
      final e = pairedFleetEntry(testPairedHost(), reading, now)!;
      expect(e.pairedId, 'p1');
      expect(e.route, ChannelRoute.lan);
      expect(e.presence, Presence.live);
      expect(e.error, isNull);
      expect(e.lastSeen, now);
      expect(e.instance.hostname, 'host-a');
      expect(e.instance.channel, 'stable');
      expect(e.instance.version, '0.60.0');
      expect(e.instance.installId, testInstallId);
      expect((e.instance.address, e.instance.port), ('198.51.100.20', 29800));
      // No fleet key: only the pairing reaches it.
      expect(e.instance.authKey, isEmpty);
      expect(e.instance.agents.single.name, 'AgentA');
    });

    test('a failure after a read dims it and keeps the agents', () {
      final reading = const PairedReading()
          .after(PairedPollOk(_snapshot()), now)
          .after(const PairedPollFailed(ChannelError.unreachable), now);
      final e = pairedFleetEntry(testPairedHost(), reading, now)!;
      expect(e.presence, Presence.stale);
      expect(e.error, ChannelError.unreachable);
      expect(e.lastSeen, now);
      expect(e.instance.agents.single.name, 'AgentA');
    });

    test('a read older than a minute is no longer live', () {
      final reading =
          const PairedReading().after(PairedPollOk(_snapshot()), now);
      final later = now.add(staleAfter);
      expect(pairedFleetEntry(testPairedHost(), reading, later)!.presence,
          Presence.stale);
    });

    test('a refused pairing shows as such, read or not', () {
      final e = pairedFleetEntry(testPairedHost(invalid: true), null, now)!;
      expect(e.error, ChannelError.unauthorized);
      expect(e.presence, Presence.stale);
      expect(e.instance.hostname, 'host-a');
    });
  });

  group('PairedHostPoller', () {
    test('reads a new target at once, then every 10 s, until stopped', () {
      fakeAsync((async) {
        final reads = <String>[];
        final results = <PairedPollResult>[];
        final poller = PairedHostPoller(
          fetch: (h) async {
            reads.add(h.id);
            return _snapshot();
          },
          onResult: (_, r) => results.add(r),
        );
        poller.sync([testPairedHost()]);
        async.flushMicrotasks();
        expect(reads, ['p1']);
        expect(results.single, isA<PairedPollOk>());

        // The same target again is not a new read.
        poller.sync([testPairedHost()]);
        async.flushMicrotasks();
        expect(reads, hasLength(1));

        async.elapse(PairedHostPoller.interval);
        expect(reads, hasLength(2));

        poller.stop();
        async.elapse(const Duration(minutes: 1));
        expect(reads, hasLength(2));
      });
    });

    test('a target dropped mid-read is not reported', () {
      fakeAsync((async) {
        final results = <PairedPollResult>[];
        final poller = PairedHostPoller(
          fetch: (_) => Future.delayed(
              const Duration(seconds: 1), () => _snapshot()),
          onResult: (_, r) => results.add(r),
        );
        poller.sync([testPairedHost()]);
        poller.sync(const <PairedHost>[]);
        async.elapse(const Duration(seconds: 2));
        expect(results, isEmpty);
        poller.stop();
      });
    });

    test('maps a 401 to unauthorized and anything else to unreachable', () {
      fakeAsync((async) {
        final results = <String, PairedPollResult>{};
        final poller = PairedHostPoller(
          fetch: (h) async => h.id == 'p1'
              ? throw const ViewerUnauthorized()
              : throw StateError('down'),
          onResult: (h, r) => results[h.id] = r,
        );
        poller.sync([
          testPairedHost(),
          testPairedHost(id: 'p2', hostname: 'host-b', installId: null),
        ]);
        async.flushMicrotasks();
        expect((results['p1']! as PairedPollFailed).error,
            ChannelError.unauthorized);
        expect((results['p2']! as PairedPollFailed).error,
            ChannelError.unreachable);
        poller.stop();
      });
    });
  });
}
