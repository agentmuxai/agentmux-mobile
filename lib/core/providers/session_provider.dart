import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/block.dart';
import '../models/tab.dart';
import '../models/workspace.dart';
import '../rpc/rpc_types.dart';
import 'connection_provider.dart';

/// All workspaces from the connected backend.
final workspacesProvider =
    FutureProvider<List<WorkspaceListEntry>>((ref) async {
  final connState = ref.watch(rpcConnectionStateProvider);
  if (connState.value != RpcConnectionState.connected) return [];

  final client = ref.read(rpcClientProvider);
  final raw = await client.listWorkspaces();
  return raw
      .map((e) =>
          WorkspaceListEntry.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Blocks for a specific tab.
final tabBlocksProvider =
    FutureProvider.family<List<Block>, String>((ref, tabId) async {
  final client = ref.read(rpcClientProvider);
  final tabData = await client.getObject('tab:$tabId');
  final tab = WaveTab.fromJson(tabData);

  final blocks = <Block>[];
  for (final blockId in tab.blockIds) {
    final blockData = await client.getObject('block:$blockId');
    blocks.add(Block.fromJson(blockData));
  }
  return blocks;
});

/// All terminal and agent blocks across all tabs (flat list for session browser).
final allSessionsProvider = FutureProvider<List<Block>>((ref) async {
  final connState = ref.watch(rpcConnectionStateProvider);
  if (connState.value != RpcConnectionState.connected) return [];

  final client = ref.read(rpcClientProvider);
  final raw = await client.call<List<dynamic>>('blockslist', {
    'filter': {'view': ['term', 'agent']},
  });
  return raw
      .map((e) => Block.fromJson(e as Map<String, dynamic>))
      .toList();
});
