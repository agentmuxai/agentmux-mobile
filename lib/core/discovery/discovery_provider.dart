import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import 'discovery_telemetry.dart';
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

class DiscoveryScanning extends DiscoveryState {
  const DiscoveryScanning();
}

class DiscoveryResults extends DiscoveryState {
  const DiscoveryResults(this.instances);
  final List<LanInstance> instances;
}

class DiscoveryEmpty extends DiscoveryState {
  const DiscoveryEmpty();
}

class DiscoveryError extends DiscoveryState {
  const DiscoveryError(this.message);
  final String message;
}

// ─── providers ───────────────────────────────────────────────────────────────

final mdnsScannerProvider = Provider<MdnsScanner>((_) => MdnsScanner());

final udpBroadcastProberProvider =
    Provider<UdpBroadcastProber>((_) => UdpBroadcastProber());

final discoveryProvider =
    AsyncNotifierProvider<DiscoveryNotifier, DiscoveryState>(
        DiscoveryNotifier.new);

// ─── notifier ────────────────────────────────────────────────────────────────

class DiscoveryNotifier extends AsyncNotifier<DiscoveryState> {
  static const _timeout = Duration(seconds: 5);
  // Layer-2 fallback (UDP broadcast probe). Only run when mDNS came back
  // empty, so this never stacks on top of the common case where mDNS just
  // works — kept short since it's a last resort, not the primary path.
  static const _udpProbeTimeout = Duration(seconds: 2);

  // Persists across refresh() calls within a session.
  final _manualInstances = <LanInstance>[];

  @override
  Future<DiscoveryState> build() async {
    state = const AsyncValue.data(DiscoveryScanning());

    // One network-environment snapshot per scan session — the single piece
    // of information that would have made "why isn't anything showing up"
    // diagnosable in-app instead of requiring a manual `adb shell ip addr`
    // detour (confirmed live 2026-08-18 on the emulator's isolated 10.0.2.x
    // NAT). See docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md.
    final snapshot = await captureNetworkSnapshot();
    // Reset first: lastMdnsSummary/lastUdpSummary must not carry over from a
    // prior scan session — e.g. if mDNS succeeds this time and the UDP
    // fallback below never runs, a stale UDP outcome from an earlier session
    // would otherwise still show in DebugLogScreen's summary header.
    DiscoveryTelemetry.reset();
    DiscoveryTelemetry.lastNetworkSnapshot = snapshot;
    AppLogger.log('Network snapshot: ${snapshot.format()}',
        name: 'DiscoveryNotifier');
    if (snapshot.hint != null) {
      AppLogger.log('Network hint: ${snapshot.hint}', name: 'DiscoveryNotifier');
    }

    // Dev emulator bootstrap: auto-connect to the host sidecar when launched via
    // scripts/run-emulator.sh (passes --dart-define=AGENTMUX_DEV_ADDR/KEY).
    await _maybeAutoConnect();

    // Tracked separately from _manualInstances: whether to fall through to the
    // UDP broadcast probe below must depend on whether mDNS itself found
    // anything, not on whether the merged (manual + mDNS) list is non-empty.
    // _mergeWithManual() always includes _manualInstances, so checking the
    // merged list here would make the UDP fallback silently never run
    // whenever dev auto-connect (or addManual()) had already seeded an
    // instance — which is exactly the case where a user most wants to see
    // what else is on the real LAN, not just the one already-known host.
    final mdnsInstances = <LanInstance>[];

    await ref
        .read(mdnsScannerProvider)
        .scan()
        .timeout(_timeout, onTimeout: (sink) => sink.close())
        .asyncMap(_enrichWithAgents)
        .forEach((instance) {
      if (!mdnsInstances.any(
          (m) => m.address == instance.address && m.port == instance.port)) {
        mdnsInstances.add(instance);
      }
      state = AsyncValue.data(DiscoveryResults(_mergeWithManual(mdnsInstances)));
    });

    if (mdnsInstances.isNotEmpty) {
      return DiscoveryResults(_mergeWithManual(mdnsInstances));
    }

    // mDNS found nothing — corporate/guest WiFi often filters multicast, so
    // fall back to a UDP broadcast probe with its own short internal
    // timeout before giving up. Runs regardless of manual/dev auto-connect
    // entries, since those describe one already-known instance and say
    // nothing about what else is reachable on the LAN.
    final udpInstances = <LanInstance>[];
    await ref
        .read(udpBroadcastProberProvider)
        // tryEmulatorRelay: only meaningful (and only sent) when the network
        // snapshot looks like the emulator's QEMU/SLIRP NAT — see
        // scripts/discovery_relay.dart's doc comment. Inert everywhere else,
        // including a real device, which has no 10.0.2.2 gateway at all.
        .probe(timeout: _udpProbeTimeout, tryEmulatorRelay: snapshot.looksLikeEmulatorNat)
        .asyncMap(_enrichWithAgents)
        // Applied after asyncMap, not just around the raw probe stream: a
        // slow/unreachable host's fetchAgents() call (5s connect + 10s
        // receive timeout in local_api_client.dart) would otherwise keep
        // this "short UDP fallback" blocked for up to ~15s per instance.
        // This doesn't cancel that in-flight call, but it does stop
        // forEach() below from waiting on it past _udpProbeTimeout.
        .timeout(_udpProbeTimeout, onTimeout: (sink) => sink.close())
        .forEach((instance) {
      if (!udpInstances.any(
          (m) => m.address == instance.address && m.port == instance.port)) {
        udpInstances.add(instance);
      }
      state =
          AsyncValue.data(DiscoveryResults(_mergeWithManual(udpInstances)));
    });

    final fallbackResult = _mergeWithManual(udpInstances);
    if (fallbackResult.isEmpty) return const DiscoveryEmpty();
    return DiscoveryResults(fallbackResult);
  }

  Future<void> refresh() async {
    state = const AsyncValue.data(DiscoveryScanning());
    ref.invalidateSelf();
  }

  /// Connect to a LAN instance by address/port/authKey without mDNS.
  /// Fetches version and agents from the instance, then merges into state.
  Future<void> addManual(String address, int port, String authKey) async {
    final client = LocalApiClient.fromParts(address, port, authKey);
    final info = await client.fetchDiscoveryInfo();
    final instance = LanInstance(
      hostname: address,
      version: info.version,
      address: address,
      port: port,
      authKey: authKey,
      agents: info.agents,
    );

    // Replace any existing manual entry with the same address:port.
    _manualInstances.removeWhere(
        (m) => m.address == address && m.port == port);
    _manualInstances.insert(0, instance);

    // Patch current state immediately without re-scanning.
    final current = switch (state.valueOrNull) {
      DiscoveryResults(:final instances) => List<LanInstance>.from(instances),
      _ => <LanInstance>[],
    };
    current.removeWhere((m) => m.address == address && m.port == port);
    current.insert(0, instance);
    state = AsyncValue.data(DiscoveryResults(current));
  }

  // If AGENTMUX_DEV_ADDR/KEY dart-defines are set (emulator dev workflow), fetch
  // the instance and seed _manualInstances so build() includes it automatically.
  Future<void> _maybeAutoConnect() async {
    if (_kDevAddr.isEmpty || _kDevKey.isEmpty) return;
    final parts = _kDevAddr.split(':');
    if (parts.length != 2) return;
    final port = int.tryParse(parts[1]);
    if (port == null) return;
    final address = parts[0];
    if (_manualInstances.any((m) => m.address == address && m.port == port)) return;
    try {
      final client = LocalApiClient.fromParts(address, port, _kDevKey);
      final info = await client.fetchDiscoveryInfo();
      _manualInstances.insert(0, LanInstance(
        hostname: address,
        version: info.version,
        address: address,
        port: port,
        authKey: _kDevKey,
        agents: info.agents,
      ));
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

  List<LanInstance> _mergeWithManual(List<LanInstance> scanned) {
    final merged = <LanInstance>[..._manualInstances];
    for (final inst in scanned) {
      if (!merged.any((m) => m.address == inst.address && m.port == inst.port)) {
        merged.add(inst);
      }
    }
    return merged;
  }

  Future<LanInstance> _enrichWithAgents(LanInstance instance) async {
    final agents = await LocalApiClient(instance).fetchAgents();
    if (agents.isEmpty) return instance;
    return instance.copyWith(agents: agents);
  }
}
