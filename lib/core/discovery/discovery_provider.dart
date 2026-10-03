import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fleet/channel_session.dart';
import '../fleet/fleet_store.dart';
import '../fleet/fleet_transport.dart';
import '../logging/app_logger.dart';
import 'discovery_telemetry.dart';
import 'host_tree.dart';
import 'local_api_client.dart';
import 'mdns_scanner.dart';
import 'models/lan_instance.dart';
import 'network_environment.dart';
import 'udp_broadcast_prober.dart';

// Compile-time constants injected by scripts/run-emulator.sh via --dart-define.
// Empty strings in production / normal flutter run (no defines passed).
const _kDevAddr = String.fromEnvironment('AGENTMUX_DEV_ADDR');
const _kDevKey = String.fromEnvironment('AGENTMUX_DEV_KEY');

// ─── state ───────────────────────────────────────────────────────────────────

sealed class DiscoveryState {
  const DiscoveryState();
}

/// The first discovery round has not finished and nothing is known yet.
class DiscoveryScanning extends DiscoveryState {
  const DiscoveryScanning();
}

class DiscoveryResults extends DiscoveryState {
  const DiscoveryResults(this.hosts);
  final List<HostNode> hosts;
}

/// A round finished and no channel is known.
class DiscoveryEmpty extends DiscoveryState {
  const DiscoveryEmpty();
}

// ─── providers ───────────────────────────────────────────────────────────────

final mdnsScannerProvider = Provider<MdnsScanner>((_) => MdnsScanner());

final udpBroadcastProberProvider =
    Provider<UdpBroadcastProber>((_) => UdpBroadcastProber());

typedef FleetTransportFactory = FleetTransport Function(
  String address,
  int port,
  String authKey,
);

/// How sessions reach a channel; overridden in tests.
final fleetTransportFactoryProvider = Provider<FleetTransportFactory>(
  (_) => (address, port, authKey) =>
      HttpFleetTransport(address, port, authKey),
);

final networkSnapshotProvider =
    Provider<Future<NetworkSnapshot> Function()>((_) => captureNetworkSnapshot);

/// Whether discovery pauses in the background (spec P10). Off in unit tests
/// that run without a widgets binding.
final followAppLifecycleProvider = Provider<bool>((_) => true);

final discoveryProvider =
    NotifierProvider<DiscoveryNotifier, DiscoveryState>(DiscoveryNotifier.new);

// ─── notifier ────────────────────────────────────────────────────────────────

/// Keeps the host -> channel -> agent tree current for as long as the app is
/// in the foreground (`docs/specs/SPEC_LIVE_FLEET_TOPOLOGY_2026_10_03.md`).
///
/// Discovery runs in rounds (mDNS and the UDP probe together) every 5 s for a
/// minute, then every 30 s. Every channel found gets a [ChannelSession] that
/// keeps its agents current (push stream, else polling). A [FleetStore] holds
/// the merged truth, and the tree is rebuilt from it at most every 150 ms. In
/// the background everything stops; on return it resyncs at once.
class DiscoveryNotifier extends Notifier<DiscoveryState> {
  static const mdnsWindow = Duration(seconds: 4);
  static const udpWindow = Duration(seconds: 2);
  static const burstRoundInterval = Duration(seconds: 5);
  static const steadyRoundInterval = Duration(seconds: 30);
  static const burstLength = Duration(minutes: 1);
  static const tickInterval = Duration(seconds: 5);
  static const emitCoalesce = Duration(milliseconds: 150);

  /// After coming back to the foreground, nothing is pruned for this long, so
  /// channels that went quiet while the app slept get a chance to answer
  /// before they are treated as gone.
  static const resumeGrace = Duration(seconds: 15);

  FleetStore _store = const FleetStore();
  final _sessions = <String, ChannelSession>{};
  int _nextId = 0;

  Timer? _roundTimer;
  Timer? _tickTimer;
  Timer? _emitTimer;
  DateTime _burstUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _graceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _paused = false;
  bool _disposed = false;
  Future<void>? _roundInFlight;
  bool _firstRoundDone = false;
  bool _logNextRound = true;
  String? _networkSignature;
  AppLifecycleListener? _lifecycle;

  @override
  DiscoveryState build() {
    ref.onDispose(_dispose);
    if (ref.read(followAppLifecycleProvider)) {
      _lifecycle = AppLifecycleListener(onPause: _pause, onResume: _resume);
    }
    scheduleMicrotask(_start);
    return const DiscoveryScanning();
  }

  /// Pull-to-refresh: one round now, every session skips its wait, and the
  /// fast round interval starts again.
  Future<void> refresh() {
    _burstUntil = clock.now().add(burstLength);
    for (final s in _sessions.values) {
      s.resync();
    }
    return _round();
  }

  /// Connect to an instance by address/port/key without discovery (QR or
  /// manual entry). Throws if the instance cannot be read, for the caller to
  /// show. The channel is kept until the user removes it.
  Future<void> addManual(String address, int port, String authKey) async {
    await _connectDirect(address, port, authKey, EndpointSource.manual);
  }

  // ─── lifecycle ─────────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (_disposed) return;
    _burstUntil = clock.now().add(burstLength);
    _tickTimer = Timer.periodic(tickInterval, (_) => _tick());
    await _maybeAutoConnect();
    unawaited(_round());
  }

  void _pause() {
    if (_paused || _disposed) return;
    _paused = true;
    _roundTimer?.cancel();
    for (final s in _sessions.values) {
      s.stop();
    }
    _sessions.clear();
  }

  void _resume() {
    if (!_paused || _disposed) return;
    _paused = false;
    final now = clock.now();
    _burstUntil = now.add(burstLength);
    _graceUntil = now.add(resumeGrace);
    _logNextRound = true;
    for (final id in _store.records.keys) {
      _startSession(id);
    }
    unawaited(_round());
  }

  void _dispose() {
    _disposed = true;
    _roundTimer?.cancel();
    _tickTimer?.cancel();
    _emitTimer?.cancel();
    for (final s in _sessions.values) {
      s.stop();
    }
    _sessions.clear();
    _lifecycle?.dispose();
  }

  // ─── discovery rounds ──────────────────────────────────────────────────────

  Future<void> _round() => _roundInFlight ??= _runRound().whenComplete(() {
        _roundInFlight = null;
      });

  Future<void> _runRound() async {
    if (_paused || _disposed) return;
    _roundTimer?.cancel();
    final logSummary = _logNextRound;
    _logNextRound = false;
    var scanned = false;
    try {
      final snapshot = await ref.read(networkSnapshotProvider)();
      if (_disposed || _paused) return;
      _noteNetwork(snapshot);
      scanned = true;
      await Future.wait([
        _listenWithin(
          ref.read(mdnsScannerProvider).scan(logSummary: logSummary),
          mdnsWindow,
        ),
        _listenWithin(
          ref.read(udpBroadcastProberProvider).probe(
                timeout: udpWindow,
                // Only meaningful (and only sent) when the network snapshot
                // looks like the emulator's QEMU/SLIRP NAT — see
                // scripts/discovery_relay.dart's doc comment.
                tryEmulatorRelay: snapshot.looksLikeEmulatorNat,
                logSummary: logSummary,
              ),
          udpWindow,
        ),
      ]);
    } catch (e, stackTrace) {
      AppLogger.log(
        'Discovery round failed',
        name: 'DiscoveryNotifier',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      if (!_disposed) {
        if (scanned) _firstRoundDone = true;
        _scheduleEmit();
        _scheduleNextRound();
      }
    }
  }

  /// Feeds [scan]'s sightings in for at most [window] in total, then cancels
  /// it (which ends an mDNS browse and releases its multicast lock). Not
  /// `Stream.timeout`, which is an inactivity timeout: a browse that keeps
  /// receiving records would never end. A scanner's own errors are logged
  /// inside it; one here is only logged, so one layer cannot fail the round.
  Future<void> _listenWithin(Stream<LanInstance> scan, Duration window) {
    final done = Completer<void>();
    late final StreamSubscription<LanInstance> sub;
    final timer = Timer(window, () {
      unawaited(sub.cancel());
      if (!done.isCompleted) done.complete();
    });
    sub = scan.listen(
      _onDiscovered,
      onError: (Object e, StackTrace stackTrace) => AppLogger.log(
        'Discovery scan error',
        name: 'DiscoveryNotifier',
        error: e,
        stackTrace: stackTrace,
      ),
      onDone: () {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  void _scheduleNextRound() {
    if (_paused || _disposed) return;
    _roundTimer?.cancel();
    final interval = clock.now().isBefore(_burstUntil)
        ? burstRoundInterval
        : steadyRoundInterval;
    _roundTimer = Timer(interval, () => unawaited(_round()));
  }

  /// Records the network this round ran on. A different set of local
  /// addresses means a different network: every LAN channel found on the old
  /// one is dropped and discovery starts again quickly.
  void _noteNetwork(NetworkSnapshot snapshot) {
    final signature = ([...snapshot.interfaces]..sort()).join(',');
    if (signature == _networkSignature) return;
    final changed = _networkSignature != null;
    _networkSignature = signature;
    DiscoveryTelemetry.lastNetworkSnapshot = snapshot;
    AppLogger.log('Network snapshot: ${snapshot.format()}',
        name: 'DiscoveryNotifier');
    if (snapshot.hint != null) {
      AppLogger.log('Network hint: ${snapshot.hint}', name: 'DiscoveryNotifier');
    }
    if (!changed) return;
    final lanIds = [
      for (final r in _store.records.values)
        if (r.source == EndpointSource.lan) r.id,
    ];
    for (final id in lanIds) {
      _sessions.remove(id)?.stop();
    }
    _store = _store.remove(lanIds);
    _burstUntil = clock.now().add(burstLength);
    _logNextRound = true;
    _scheduleEmit();
  }

  void _onDiscovered(LanInstance instance) =>
      _onSighting(Sighting.fromInstance(instance));

  /// Returns the id of the record the sighting landed on.
  String _onSighting(Sighting sighting) {
    final (store, id, effect) = _store.sight(
      sighting,
      clock.now(),
      newId: () => 'ch${_nextId++}',
    );
    _store = store;
    switch (effect) {
      case SightingEffect.added:
        _startSession(id);
      case SightingEffect.relocated:
        _sessions.remove(id)?.stop();
        _startSession(id);
      case SightingEffect.renewed:
        break;
    }
    _scheduleEmit();
    return id;
  }

  // ─── sessions ──────────────────────────────────────────────────────────────

  void _startSession(String id) {
    if (_paused || _disposed || _sessions.containsKey(id)) return;
    final r = _store.records[id];
    if (r == null) return;
    late final ChannelSession session;
    session = ChannelSession(
      transport: ref.read(fleetTransportFactoryProvider)(
        r.address,
        r.port,
        r.authKey,
      ),
      // A full-key connection reads /agentmux/discovery, which also reports
      // the machine's other channels; a LAN (lan_key) one uses the fleet feed.
      startMode: r.source == EndpointSource.lan
          ? SessionMode.stream
          : SessionMode.legacy,
      onUpdate: (u) {
        if (_disposed || _sessions[id] != session) return;
        _store = _store.apply(id, u, clock.now());
        _scheduleEmit();
      },
    );
    _sessions[id] = session;
    session.start();
  }

  void _tick() {
    if (_paused || _disposed) return;
    final now = clock.now();
    if (!now.isBefore(_graceUntil)) {
      final (store, gone) = _store.prune(now);
      _store = store;
      for (final id in gone) {
        _sessions.remove(id)?.stop();
      }
    }
    // Presence ages with time even when nothing arrives.
    _scheduleEmit();
  }

  // ─── view ──────────────────────────────────────────────────────────────────

  void _scheduleEmit() {
    if (_disposed || (_emitTimer?.isActive ?? false)) return;
    _emitTimer = Timer(emitCoalesce, _emit);
  }

  void _emit() {
    if (_disposed) return;
    final now = clock.now();
    final entries = [
      for (final r in _store.records.values)
        if (r.presence(now) != Presence.gone)
          FleetEntry(
            instance: r.toInstance(),
            presence: r.presence(now),
            error: r.visibleError(now),
            lastSeen: r.lastAlive,
          ),
    ];
    state = entries.isNotEmpty
        ? DiscoveryResults(buildHostTrees(entries))
        : (_firstRoundDone ? const DiscoveryEmpty() : const DiscoveryScanning());
  }

  // ─── direct connections ────────────────────────────────────────────────────

  Future<void> _connectDirect(
    String address,
    int port,
    String authKey,
    EndpointSource source,
  ) async {
    final info =
        await LocalApiClient.fromParts(address, port, authKey).fetchDiscoveryInfo();
    if (_disposed) return;
    final id = _onSighting(Sighting(
      hostname: info.hostname.isNotEmpty ? info.hostname : address,
      address: address,
      port: port,
      authKey: authKey,
      version: info.version,
      channel: info.channel,
      source: source,
    ));
    _store = _store.apply(
      id,
      SessionContact(agents: info.agents, channel: info.channel),
      clock.now(),
    );
    _scheduleEmit();
  }

  // If AGENTMUX_DEV_ADDR/KEY dart-defines are set (emulator dev workflow with
  // `scripts/dev-full.sh --dev-connect`), connect to that instance directly.
  Future<void> _maybeAutoConnect() async {
    if (_kDevAddr.isEmpty || _kDevKey.isEmpty) return;
    final parts = _kDevAddr.split(':');
    if (parts.length != 2) return;
    final port = int.tryParse(parts[1]);
    if (port == null) return;
    final address = parts[0];
    try {
      await _connectDirect(address, port, _kDevKey, EndpointSource.dev);
    } catch (e, stackTrace) {
      // Dev-only bootstrap path (scripts/run-emulator.sh) — silently doing
      // nothing here previously made "dev host unreachable" indistinguishable
      // from "dev-define wasn't passed", which cost real time diagnosing an
      // emulator/host connectivity issue with no signal to go on.
      AppLogger.log(
        devAutoConnectFailureMessage(e, address, port),
        name: 'DiscoveryNotifier',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// The log line for a failed [_maybeAutoConnect], split out so the 401
  /// special case is testable without a live server (same pattern as
  /// `LocalApiClient.fetchAgentsFailureMessage`).
  ///
  /// A 401 here specifically means the dev key is stale, and — unlike
  /// `fetchAgents()`'s generic 401 handling (see its own doc comment) — that
  /// diagnosis is actually correct in this one spot: `_kDevKey` is always the
  /// FULL instance `auth_key` (baked in at build time by `run-emulator.sh`'s
  /// `--dart-define`), and the desktop mints a fresh one on every launch
  /// (`agentmux-launcher`'s `srv_spawner.rs` — "Generate a fresh auth_key per
  /// run"). So any AgentMux restart invalidates it, and rebuilding really is
  /// the fix — Codex P2 on agentmux-mobile#20/#21 was right that this
  /// diagnosis belongs here, not in the shared `fetchAgents()` path that
  /// mDNS/UDP-scoped (`lan_key`) instances also go through, where the same
  /// advice would be wrong.
  @visibleForTesting
  static String devAutoConnectFailureMessage(
    Object error,
    String address,
    int port,
  ) {
    final isStaleDevKey =
        error is DioException && error.response?.statusCode == 401;
    if (!isStaleDevKey) {
      return 'Dev auto-connect to $address:$port failed';
    }
    return 'Dev auto-connect to $address:$port got 401 — the dev key is '
        'almost certainly stale (the desktop mints a new one per launch; '
        'AGENTMUX_DEV_KEY is baked in at build time). Rebuild the app '
        'against the running instance.';
  }

  /// Whether [a] and [b] describe the same channel, even when reached two
  /// different ways (retro B1: dev auto-connect over loopback and UDP
  /// discovery over the LAN address of the same process). See [sameChannel]
  /// for the rule; hostname is a display-level identity signal here, not a
  /// cryptographic one (see `docs/specs/REMOTE_TERMINALS_AND_CONVERSATION_HISTORY.md`).
  @visibleForTesting
  static bool isSameInstance(LanInstance a, LanInstance b) => sameChannel(
        hostnameA: a.hostname,
        channelA: a.channel,
        addressA: a.address,
        portA: a.port,
        hostnameB: b.hostname,
        channelB: b.channel,
        addressB: b.address,
        portB: b.port,
      );
}
