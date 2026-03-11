import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection.dart';
import '../rpc/rpc_client.dart';
import '../rpc/rpc_types.dart';

/// The shared RPC client instance.
final rpcClientProvider = Provider<AgentMuxRpcClient>((ref) {
  final client = AgentMuxRpcClient();
  ref.onDispose(() => client.dispose());
  return client;
});

/// Stream of RPC connection state changes.
final rpcConnectionStateProvider =
    StreamProvider<RpcConnectionState>((ref) {
  final client = ref.watch(rpcClientProvider);
  return client.connectionState;
});

/// The currently active server connection config (null if none).
final activeConnectionProvider =
    StateProvider<ServerConnection?>((ref) => null);

/// Saved connections list (persisted to secure storage).
final savedConnectionsProvider =
    StateNotifierProvider<SavedConnectionsNotifier, List<ServerConnection>>(
        (ref) {
  return SavedConnectionsNotifier();
});

class SavedConnectionsNotifier extends StateNotifier<List<ServerConnection>> {
  SavedConnectionsNotifier() : super([]);

  /// Load saved connections from secure storage.
  Future<void> load() async {
    // TODO: Load from flutter_secure_storage
    state = [];
  }

  /// Add a new connection and persist.
  Future<void> add(ServerConnection connection) async {
    state = [...state, connection];
    // TODO: Persist to flutter_secure_storage
  }

  /// Remove a connection by ID.
  Future<void> remove(String id) async {
    state = state.where((c) => c.id != id).toList();
    // TODO: Persist to flutter_secure_storage
  }

  /// Update an existing connection.
  Future<void> update(ServerConnection connection) async {
    state = [
      for (final c in state)
        if (c.id == connection.id) connection else c,
    ];
    // TODO: Persist to flutter_secure_storage
  }
}

/// Connect to a backend server.
final connectActionProvider =
    Provider<Future<void> Function(ServerConnection)>((ref) {
  return (ServerConnection conn) async {
    final client = ref.read(rpcClientProvider);
    await client.connect(conn.host, conn.port, conn.authKey,
        useTls: conn.useTls);
    ref.read(activeConnectionProvider.notifier).state = conn;
  };
});
