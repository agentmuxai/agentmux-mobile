import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_api_client.dart';
import 'mdns_scanner.dart';
import 'models/lan_instance.dart';

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

final discoveryProvider =
    AsyncNotifierProvider<DiscoveryNotifier, DiscoveryState>(
        DiscoveryNotifier.new);

// ─── notifier ────────────────────────────────────────────────────────────────

class DiscoveryNotifier extends AsyncNotifier<DiscoveryState> {
  static const _timeout = Duration(seconds: 5);

  // Persists across refresh() calls within a session.
  final _manualInstances = <LanInstance>[];

  @override
  Future<DiscoveryState> build() async {
    state = const AsyncValue.data(DiscoveryScanning());

    // Dev emulator bootstrap: auto-connect to the host sidecar when launched via
    // scripts/run-emulator.sh (passes --dart-define=AGENTMUX_DEV_ADDR/KEY).
    await _maybeAutoConnect();

    final instances = <LanInstance>[..._manualInstances];

    await ref
        .read(mdnsScannerProvider)
        .scan()
        .timeout(_timeout, onTimeout: (sink) => sink.close())
        .asyncMap(_enrichWithAgents)
        .forEach((instance) {
      // Skip mDNS results that duplicate a manually-added entry.
      if (!instances.any(
          (m) => m.address == instance.address && m.port == instance.port)) {
        instances.add(instance);
      }
      state = AsyncValue.data(DiscoveryResults(List.from(instances)));
    });

    if (instances.isEmpty) return const DiscoveryEmpty();
    return DiscoveryResults(List.from(instances));
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
    } catch (_) {}
  }

  Future<LanInstance> _enrichWithAgents(LanInstance instance) async {
    final agents = await LocalApiClient(instance).fetchAgents();
    if (agents.isEmpty) return instance;
    return instance.copyWith(agents: agents);
  }
}
