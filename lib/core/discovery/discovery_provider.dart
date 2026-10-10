import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_provider.dart';
import '../auth/auth_provider.dart';
import '../fleet/channel_session.dart';
import '../fleet/cloud_instance_source.dart';
import '../fleet/cloud_instances.dart';
import '../fleet/fleet_store.dart';
import '../fleet/fleet_transport.dart';
import '../logging/app_logger.dart';
import '../viewer/paired_host.dart';
import '../viewer/paired_host_source.dart';
import '../viewer/paired_hosts_repository.dart';
import '../viewer/paired_match.dart';
import '../viewer/pairing_service.dart';
import 'bonjour_scanner.dart';
import 'discovery_telemetry.dart';
import 'host_tree.dart';
import 'lan_scanner.dart';
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
  const DiscoveryResults(this.hosts, {this.cloud = CloudListStatus.pending});
  final List<HostNode> hosts;

  /// What the cloud host list says, for the note under the list.
  final CloudListStatus cloud;
}

/// A round finished and no channel is known.
class DiscoveryEmpty extends DiscoveryState {
  const DiscoveryEmpty({this.cloud = CloudListStatus.pending});
  final CloudListStatus cloud;
}

// ─── providers ───────────────────────────────────────────────────────────────

final mdnsScannerProvider = Provider<MdnsScanner>((_) => MdnsScanner());

final bonjourScannerProvider = Provider<LanScanner>((_) => BonjourScanner());

/// The platform discovery runs on; overridden in tests.
final discoveryPlatformProvider =
    Provider<TargetPlatform>((_) => defaultTargetPlatform);

/// How this platform browses the LAN: the system's Bonjour browser on iOS
/// (raw multicast needs an entitlement there), `multicast_dns` elsewhere.
final lanScannerProvider = Provider<LanScanner>(
  (ref) => switch (lanBrowseMethodFor(ref.watch(discoveryPlatformProvider))) {
    LanBrowseMethod.bonjour => ref.watch(bonjourScannerProvider),
    LanBrowseMethod.multicastDns => ref.watch(mdnsScannerProvider),
  },
);

/// Reads a paired computer over its viewer listener; overridden in tests.
final pairedHostFetchProvider = Provider<PairedFetch>(
  (ref) => viewerPairedFetch(ref.watch(viewerClientFactoryProvider)),
);

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

/// Whether the phone is signed in to the cloud; overridden in tests.
final cloudSignedInProvider = Provider<Future<bool> Function()>(
  (ref) => ref.watch(authRepositoryProvider).isAuthenticated,
);

/// Reads the account's cloud install list; overridden in tests.
final cloudInstancesFetchProvider =
    Provider<Future<List<CloudInstance>> Function()>(
  (ref) => ref.watch(muxbusClientProvider).getInstances,
);

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
///
/// When signed in, a [CloudInstanceSource] feeds the account's installs into
/// the same store as cloud channels
/// (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 5); the
/// tree joins a cloud channel to a LAN one only by install id.
///
/// A paired computer always shows: one that discovery has not found is read
/// over its pinned viewer listener by a [PairedHostPoller] (every 10 s) and
/// joins the tree as its own channel; once discovery finds the same channel
/// (install id, else hostname and channel), the discovered one is shown
/// instead.
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
  CloudInstanceSource? _cloud;
  CloudListStatus _cloudStatus = CloudListStatus.pending;
  PairedHostPoller? _paired;
  final _pairedReadings = <String, PairedReading>{};

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
  String? _snapshotText;
  String? _lanSignature;
  AppLifecycleListener? _lifecycle;

  @override
  DiscoveryState build() {
    ref.onDispose(_dispose);
    // Pairing or unpairing changes what the host cards show.
    ref.listen(pairedHostsProvider, (_, __) => _scheduleEmit());
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
    return Future.wait([
      _round(),
      refreshCloud(),
      _paired?.pollNow() ?? Future<void>.value(),
    ]);
  }

  /// Reads the cloud install list now (pull-to-refresh, or after signing in
  /// or out).
  Future<void> refreshCloud() => _cloud?.refresh() ?? Future.value();

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
    _startCloud();
    _startPaired();
    await _maybeAutoConnect();
    unawaited(_round());
  }

  /// The app went to the background. Called by the lifecycle listener;
  /// public so tests can drive it without a widgets binding.
  @visibleForTesting
  void handlePause() => _pause();

  /// The app came back to the foreground.
  @visibleForTesting
  void handleResume() => _resume();

  void _pause() {
    if (_paused || _disposed) return;
    _paused = true;
    _roundTimer?.cancel();
    for (final s in _sessions.values) {
      s.stop();
    }
    _sessions.clear();
    _cloud?.stop();
    _cloud = null;
    _paired?.stop();
    _paired = null;
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
    _startCloud();
    _startPaired();
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
    _cloud?.stop();
    _cloud = null;
    _paired?.stop();
    _paired = null;
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
      final platform = ref.read(discoveryPlatformProvider);
      await Future.wait([
        _listenWithin(
          ref.read(lanScannerProvider).scan(logSummary: logSummary),
          mdnsWindow,
        ),
        // iOS refuses a broadcast send without the multicast entitlement.
        if (udpProbeSupportedOn(platform))
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

  /// Records the network this round ran on.
  ///
  /// Only a change of [lanNetworkSignature] (the private IPv4 subnets of
  /// non-cellular interfaces) is a new network: IPv6 privacy addresses and
  /// mobile data come and go on their own, and an empty interface list means
  /// "unknown", not "changed". On a real change every LAN session reconnects
  /// over the new network and discovery runs fast again. Nothing is deleted:
  /// hosts that belonged to the old network stop answering, dim, and age out
  /// like any other quiet channel, so the screen never blanks.
  void _noteNetwork(NetworkSnapshot snapshot) {
    final text = ([...snapshot.interfaces]..sort()).join(',');
    if (text != _snapshotText) {
      _snapshotText = text;
      DiscoveryTelemetry.lastNetworkSnapshot = snapshot;
      AppLogger.log('Network snapshot: ${snapshot.format()}',
          name: 'DiscoveryNotifier');
      if (snapshot.hint != null) {
        AppLogger.log('Network hint: ${snapshot.hint}',
            name: 'DiscoveryNotifier');
      }
    }
    final signature = lanNetworkSignature(snapshot.interfaces);
    if (signature == null || signature == _lanSignature) return;
    final changed = _lanSignature != null;
    _lanSignature = signature;
    if (!changed) return;
    AppLogger.log('Local network changed ($signature); reconnecting',
        name: 'DiscoveryNotifier');
    final lanIds = [
      for (final r in _store.records.values)
        if (r.source == EndpointSource.lan) r.id,
    ];
    for (final id in lanIds) {
      _sessions.remove(id)?.stop();
      _startSession(id);
    }
    _burstUntil = clock.now().add(burstLength);
    _logNextRound = true;
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

  // ─── cloud ─────────────────────────────────────────────────────────────────

  void _startCloud() {
    if (_paused || _disposed || _cloud != null) return;
    late final CloudInstanceSource source;
    source = CloudInstanceSource(
      isSignedIn: ref.read(cloudSignedInProvider),
      fetch: ref.read(cloudInstancesFetchProvider),
      onUpdate: (u) {
        if (_disposed || _cloud != source) return;
        _onCloud(u);
      },
    );
    _cloud = source;
    source.start();
  }

  void _onCloud(CloudUpdate u) {
    switch (u) {
      case CloudSignedOut():
        _store = _store.clearCloud();
        _cloudStatus = CloudListStatus.signedOut;
      case CloudFetched(:final instances):
        _store = _store.syncCloud(instances);
        _cloudStatus = CloudListStatus.ok;
      case CloudUnavailable():
        // What was listed stays, dimming by its own age (spec 3.5).
        _cloudStatus = CloudListStatus.unavailable;
      case CloudUnsupported():
        _cloudStatus = CloudListStatus.unsupported;
    }
    _scheduleEmit();
  }

  // ─── paired computers ──────────────────────────────────────────────────────

  void _startPaired() {
    if (_paused || _disposed || _paired != null) return;
    late final PairedHostPoller poller;
    poller = PairedHostPoller(
      fetch: ref.read(pairedHostFetchProvider),
      onResult: (host, result) {
        if (_disposed || _paired != poller) return;
        _onPaired(host, result);
      },
    );
    _paired = poller;
    // Its targets come from the next emit, which knows what discovery found.
    _scheduleEmit();
  }

  void _onPaired(PairedHost host, PairedPollResult result) {
    _pairedReadings[host.id] =
        (_pairedReadings[host.id] ?? const PairedReading())
            .after(result, clock.now());
    if (result case PairedPollFailed(error: ChannelError.unauthorized)) {
      // The existing "Pair again": the computer revoked this device.
      unawaited(ref.read(pairedHostsProvider.notifier).markInvalid(host.id));
    }
    _scheduleEmit();
  }

  // ─── sessions ──────────────────────────────────────────────────────────────

  void _startSession(String id) {
    if (_paused || _disposed || _sessions.containsKey(id)) return;
    final r = _store.records[id];
    // A cloud channel has no endpoint to hold a session with.
    if (r == null || r.source == EndpointSource.cloud) return;
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
    // Right after coming back to the foreground, what went quiet while the
    // app slept is shown dimmed, not hidden, until it has had a chance to
    // answer (see [resumeGrace]).
    final inGrace = now.isBefore(_graceUntil);
    final entries = <FleetEntry>[];
    for (final r in _store.records.values) {
      var presence = r.presence(now);
      if (presence == Presence.gone) {
        if (!inGrace) continue;
        presence = Presence.stale;
      }
      entries.add(FleetEntry(
        instance: r.toInstance(),
        presence: presence,
        error: r.visibleError(now),
        lastSeen: r.lastAlive,
        route: r.route,
      ));
    }
    final paired = ref.read(pairedHostsProvider);
    // A failed read leaves cloud records aging: that is this device falling
    // behind, not an install that stopped publishing.
    final cloudCurrent = _cloudStatus == CloudListStatus.ok;
    var hosts = entries.isEmpty
        ? const <HostNode>[]
        : applyPairings(
            buildHostTrees(entries, cloudListCurrent: cloudCurrent), paired);
    final pairedEntries = _pairedEntries(hosts, entries, paired, now);
    if (pairedEntries.isNotEmpty) {
      entries.addAll(pairedEntries);
      hosts = applyPairings(
          buildHostTrees(entries, cloudListCurrent: cloudCurrent), paired);
    }
    _followMovedPairings(hosts);
    state = entries.isNotEmpty
        ? DiscoveryResults(hosts, cloud: _cloudStatus)
        : (_firstRoundDone
            ? DiscoveryEmpty(cloud: _cloudStatus)
            : const DiscoveryScanning());
  }

  /// The paired computers discovery has not found, as entries of their own;
  /// and which of them the poller reads (all but those the computer refused).
  ///
  /// One whose install is also in the cloud list joins that cloud channel
  /// while it answers; while it does not, the cloud channel shows alone, as
  /// before, so its agents keep the cloud screen off the LAN.
  List<FleetEntry> _pairedEntries(
    List<HostNode> hosts,
    List<FleetEntry> discovered,
    List<PairedHost> paired,
    DateTime now,
  ) {
    final found = {
      for (final h in hosts)
        for (final c in h.channels)
          if (c.pairing != null) c.pairing!.paired.id,
    };
    final missing = [
      for (final p in paired)
        if (!found.contains(p.id)) p,
    ];
    _pairedReadings.removeWhere((id, _) => !paired.any((p) => p.id == id));
    _paired?.sync([
      for (final p in missing)
        if (!p.invalid) p,
    ]);
    final cloudIds = {
      for (final e in discovered)
        if (e.isCloud && e.instance.installId != null) e.instance.installId!,
    };
    return [
      for (final p in missing)
        if (pairedFleetEntry(p, _pairedReadings[p.id], now) case final e?)
          if (e.presence == Presence.live ||
              !cloudIds.contains(e.instance.installId))
            e,
    ];
  }

  /// Where each paired channel's viewer listener was last asked to move to,
  /// so a move is stored once, not on every emit until the store catches up.
  final _requestedMoves = <String, String>{};

  /// Stores the address and `viewer_port` discovery reports for a paired
  /// host that answers, so the pairing still works after the desktop changes
  /// address or port, even before discovery finds it next time.
  void _followMovedPairings(List<HostNode> hosts) {
    for (final h in hosts) {
      for (final c in h.channels) {
        final m = c.pairing;
        if (m == null || !m.moved || c.presence != Presence.live) continue;
        final target = '${m.host}:${m.port}';
        if (_requestedMoves[m.paired.id] == target) continue;
        _requestedMoves[m.paired.id] = target;
        unawaited(ref
            .read(pairedHostsProvider.notifier)
            .updateEndpoint(m.paired.id, m.host, m.port));
      }
    }
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
  /// special case is testable without a live server.
  ///
  /// A 401 here specifically means the dev key is stale, and that diagnosis
  /// is correct in this one spot only: `_kDevKey` is always the FULL instance
  /// `auth_key` (baked in at build time by `run-emulator.sh`'s
  /// `--dart-define`), and the desktop mints a fresh one on every launch
  /// (`agentmux-launcher`'s `srv_spawner.rs` — "Generate a fresh auth_key per
  /// run"). So any AgentMux restart invalidates it, and rebuilding really is
  /// the fix. A LAN-discovered channel holds the scoped `lan_key` instead, and
  /// its 401 (a session's "not authorised") must not get this advice — Codex
  /// P2 on agentmux-mobile#20/#21.
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
