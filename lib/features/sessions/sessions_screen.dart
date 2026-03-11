import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/block.dart';
import '../../core/providers/connection_provider.dart';
import '../../core/providers/session_provider.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeConn = ref.watch(activeConnectionProvider);
    final sessions = ref.watch(allSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/connections'),
        ),
        title: Text(activeConn?.name ?? 'Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (blocks) => blocks.isEmpty
            ? _EmptySessionState(
                onNewTerminal: () => _createTerminal(ref, context),
                onNewAgent: () => _createAgent(ref, context),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: blocks.length,
                itemBuilder: (context, index) =>
                    _SessionCard(block: blocks[index]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewSessionSheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showNewSessionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('New Terminal'),
              onTap: () {
                Navigator.pop(context);
                _createTerminal(ref, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('New Agent'),
              onTap: () {
                Navigator.pop(context);
                _createAgent(ref, context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createTerminal(WidgetRef ref, BuildContext context) async {
    final client = ref.read(rpcClientProvider);
    final result = await client.createBlock({
      'meta': {'view': 'term', 'controller': 'shell'},
    });
    final blockId = result['oid'] as String;
    if (context.mounted) context.push('/terminal/$blockId');
  }

  Future<void> _createAgent(WidgetRef ref, BuildContext context) async {
    final client = ref.read(rpcClientProvider);
    final result = await client.createBlock({
      'meta': {'view': 'agent', 'controller': 'cmd'},
    });
    final blockId = result['oid'] as String;
    if (context.mounted) context.push('/agent/$blockId');
  }
}

class _EmptySessionState extends StatelessWidget {
  final VoidCallback onNewTerminal;
  final VoidCallback onNewAgent;

  const _EmptySessionState({
    required this.onNewTerminal,
    required this.onNewAgent,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No active sessions',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: onNewTerminal,
                icon: const Icon(Icons.terminal),
                label: const Text('Terminal'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onNewAgent,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Agent'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Block block;

  const _SessionCard({required this.block});

  @override
  Widget build(BuildContext context) {
    final isAgent = block.isAgent;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          isAgent ? Icons.auto_awesome : Icons.terminal,
          color: isAgent
              ? const Color(0xFFCC785C)
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          isAgent
              ? 'Agent${block.cmd.isNotEmpty ? ' — ${block.cmd}' : ''}'
              : 'Terminal${block.cmdCwd.isNotEmpty ? ' — ${block.cmdCwd}' : ''}',
        ),
        subtitle: Text(
          block.connection.isNotEmpty ? block.connection : 'Local',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final route = isAgent
              ? '/agent/${block.oid}'
              : '/terminal/${block.oid}';
          context.push(route);
        },
      ),
    );
  }
}
