import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_provider.dart';
import '../../core/api/muxbus_socket.dart';
import '../../core/models/agent.dart';

class AgentListNotifier extends AsyncNotifier<List<Agent>> {
  @override
  Future<List<Agent>> build() async {
    // Refresh the list on every inject_available signal.
    final socket = ref.watch(muxbusSocketProvider);
    final sub = socket.events.listen((event) {
      if (event.type == MuxbusEventType.injectAvailable) refresh();
    });
    ref.onDispose(sub.cancel);

    return _fetch();
  }

  Future<List<Agent>> _fetch() =>
      ref.read(muxbusClientProvider).getAgents();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

final agentListProvider =
    AsyncNotifierProvider<AgentListNotifier, List<Agent>>(
  AgentListNotifier.new,
);
