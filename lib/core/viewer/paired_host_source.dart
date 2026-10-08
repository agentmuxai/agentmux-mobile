import 'dart:async';

import 'package:clock/clock.dart';

import '../discovery/host_tree.dart';
import '../discovery/models/lan_instance.dart';
import '../discovery/peer_fields.dart';
import '../fleet/channel_session.dart';
import '../fleet/fleet_store.dart';
import '../logging/app_logger.dart';
import 'paired_host.dart';
import 'pairing_service.dart';
import 'viewer_client.dart';

/// One successful read of a paired computer's viewer listener.
class PairedSnapshot {
  const PairedSnapshot({required this.hello, required this.agents});
  final ViewerHello hello;

  /// With their state and how long, anchored at this device's clock when the
  /// answer arrived (as the fleet feed's are).
  final List<LanAgent> agents;
}

/// Reads one paired computer: `GET /agentmux/viewer/hello`, then
/// `GET /agentmux/viewer/agents`. Throws [ViewerUnauthorized] on a 401.
typedef PairedFetch = Future<PairedSnapshot> Function(PairedHost host);

/// [PairedFetch] over the pinned-TLS [ViewerClient], with the stored
/// address, port, fingerprint and token.
PairedFetch viewerPairedFetch(ViewerClientFactory clientFor) => (paired) async {
      final client = clientFor(
        host: paired.host,
        port: paired.port,
        fingerprint: paired.fingerprint,
        token: paired.token,
      );
      try {
        final hello = await client.hello();
        final list = await client.agents();
        final receivedAt = clock.now();
        final nowMs = parseUnixMs(list.nowMs);
        return PairedSnapshot(
          hello: hello,
          agents: [
            for (final a in list.agents)
              lanAgentFrom(
                a.name,
                kind: a.kind,
                status: switch (parseAgentState(a.state)) {
                  final AgentState state => ReportedAgentStatus(
                      state,
                      sinceMs: parseUnixMs(a.sinceMs),
                    ),
                  null => null,
                },
                nowMs: nowMs,
                receivedAt: receivedAt,
              ),
          ],
        );
      } finally {
        client.close();
      }
    };

/// What one poll of a pairing gave.
sealed class PairedPollResult {
  const PairedPollResult();
}

class PairedPollOk extends PairedPollResult {
  const PairedPollOk(this.snapshot);
  final PairedSnapshot snapshot;
}

class PairedPollFailed extends PairedPollResult {
  const PairedPollFailed(this.error);

  /// [ChannelError.unauthorized] when the computer refused the token.
  final ChannelError error;
}

/// The latest known about one paired computer, read over its viewer
/// listener.
class PairedReading {
  const PairedReading({
    this.hello,
    this.agents = const [],
    this.lastContact,
    this.error,
  });

  final ViewerHello? hello;
  final List<LanAgent> agents;

  /// This device's clock at the last successful read.
  final DateTime? lastContact;

  /// Why the last read failed; null when it succeeded.
  final ChannelError? error;

  /// [this] after [result], read at [now]. A failure keeps what was last
  /// known (shown dimmed), as a quiet discovered channel does.
  PairedReading after(PairedPollResult result, DateTime now) =>
      switch (result) {
        PairedPollOk(:final snapshot) => PairedReading(
            hello: snapshot.hello,
            agents: snapshot.agents,
            lastContact: now,
          ),
        PairedPollFailed(:final error) => PairedReading(
            hello: hello,
            agents: agents,
            lastContact: lastContact,
            error: error,
          ),
      };
}

/// A paired computer discovery has not found, as a [FleetEntry] for the host
/// tree, so it shows as a host card like any other channel: the hello's
/// hostname, channel and version, the agents with their state, route LAN.
///
/// Live while the last read succeeded within [staleAfter]; otherwise dimmed,
/// with what was last known. A pairing the computer refused shows as such
/// (the card's "Pair again") without being read. Null for a pairing not
/// read yet, so a card never appears empty and then fills in.
FleetEntry? pairedFleetEntry(
  PairedHost paired,
  PairedReading? reading,
  DateTime now,
) {
  if (reading == null && !paired.invalid) return null;
  final hello = reading?.hello;
  final contact = reading?.lastContact;
  final error = paired.invalid ? ChannelError.unauthorized : reading?.error;
  final live =
      error == null && contact != null && now.difference(contact) < staleAfter;
  return FleetEntry(
    instance: LanInstance(
      hostname: hello?.hostname ?? paired.hostname,
      version: hello?.version ?? '?',
      // The viewer listener; there is no fleet endpoint or key for it.
      address: paired.host,
      port: paired.port,
      authKey: '',
      channel: hello?.channel ?? paired.channel,
      installId: paired.installId ?? hello?.installId,
      viewerPort: paired.port,
      agents: reading?.agents ?? const [],
    ),
    presence: live ? Presence.live : Presence.stale,
    error: error,
    lastSeen: contact,
    route: ChannelRoute.lan,
    pairedId: paired.id,
  );
}

/// Polls the paired computers discovery has not found, every [interval]
/// while it runs; a newly added target is read at once. One-shot like a
/// channel session: the owner stops it in the background and starts a new
/// one on return. Timing reads `Timer`, so tests drive it with `fake_async`.
class PairedHostPoller {
  PairedHostPoller({required this.fetch, required this.onResult});

  final PairedFetch fetch;
  final void Function(PairedHost host, PairedPollResult result) onResult;

  static const interval = Duration(seconds: 10);

  final _targets = <String, PairedHost>{};
  final _inFlight = <String>{};
  final _lastLogged = <String, String>{};
  Timer? _timer;
  bool _stopped = false;

  /// The pairings to read: replaces the previous set. A pairing not in it
  /// any more stops being read (discovery found it, or it was removed).
  void sync(Iterable<PairedHost> targets) {
    if (_stopped) return;
    final added = <PairedHost>[];
    final next = {for (final t in targets) t.id: t};
    for (final t in next.values) {
      if (!_targets.containsKey(t.id)) added.add(t);
    }
    _targets
      ..clear()
      ..addAll(next);
    _lastLogged.removeWhere((id, _) => !next.containsKey(id));
    _timer ??= Timer.periodic(interval, (_) => unawaited(pollNow()));
    for (final t in added) {
      unawaited(_poll(t.id));
    }
  }

  /// Reads every target now (pull-to-refresh).
  Future<void> pollNow() =>
      Future.wait([for (final id in [..._targets.keys]) _poll(id)]);

  /// Ends polling for good; nothing is reported after this returns.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    _targets.clear();
  }

  Future<void> _poll(String id) async {
    final host = _targets[id];
    if (_stopped || host == null || !_inFlight.add(id)) return;
    PairedPollResult result;
    try {
      result = PairedPollOk(await fetch(host));
      _lastLogged.remove(id);
    } on ViewerUnauthorized {
      result = const PairedPollFailed(ChannelError.unauthorized);
      _log(host, 'refused this device (401)');
    } catch (e) {
      result = const PairedPollFailed(ChannelError.unreachable);
      // The type only: the token is never part of what is logged.
      _log(host, 'unreachable (${e.runtimeType})');
    } finally {
      _inFlight.remove(id);
    }
    // Not reported once stopped, or once no longer a target.
    if (_stopped || !_targets.containsKey(id)) return;
    onResult(host, result);
  }

  /// Logged once per distinct failure, not every [interval].
  void _log(PairedHost host, String what) {
    if (_lastLogged[host.id] == what) return;
    _lastLogged[host.id] = what;
    AppLogger.log('Paired computer ${host.hostname}: $what',
        name: 'PairedHosts');
  }
}
