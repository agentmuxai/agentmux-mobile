import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_api_client.dart';
import 'mdns_scanner.dart';
import 'models/lan_instance.dart';

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

  @override
  Future<DiscoveryState> build() async {
    state = const AsyncValue.data(DiscoveryScanning());
    final instances = <LanInstance>[];

    await ref
        .read(mdnsScannerProvider)
        .scan()
        .timeout(_timeout, onTimeout: (sink) => sink.close())
        .asyncMap(_enrichWithAgents)
        .forEach((instance) {
      instances.add(instance);
      state = AsyncValue.data(DiscoveryResults(List.from(instances)));
    });

    if (instances.isEmpty) return const DiscoveryEmpty();
    return DiscoveryResults(List.from(instances));
  }

  Future<void> refresh() async {
    state = const AsyncValue.data(DiscoveryScanning());
    ref.invalidateSelf();
  }

  Future<LanInstance> _enrichWithAgents(LanInstance instance) async {
    final agents = await LocalApiClient(instance).fetchAgents();
    if (agents.isEmpty) return instance;
    return instance.copyWith(agents: agents);
  }
}
