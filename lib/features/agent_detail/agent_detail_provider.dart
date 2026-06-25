import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_provider.dart';
import '../../core/api/muxbus_socket.dart';
import '../../core/models/message.dart';

class AgentDetailNotifier
    extends FamilyAsyncNotifier<List<Message>, String> {
  @override
  Future<List<Message>> build(String agentId) async {
    final socket = ref.watch(muxbusSocketProvider);
    final sub = socket.events.listen((event) {
      if (event.type == MuxbusEventType.injectAvailable) refresh(agentId);
    });
    ref.onDispose(sub.cancel);

    return _fetch(agentId);
  }

  Future<List<Message>> _fetch(String agentId) =>
      ref.read(muxbusClientProvider).getMessages(agentId, unreadOnly: false);

  Future<void> refresh(String agentId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch(agentId));
  }
}

final agentDetailProvider =
    AsyncNotifierProviderFamily<AgentDetailNotifier, List<Message>, String>(
  AgentDetailNotifier.new,
);
