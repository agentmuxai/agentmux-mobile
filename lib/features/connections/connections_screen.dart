import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/connection.dart';
import '../../core/providers/connection_provider.dart';
import '../../core/rpc/rpc_types.dart';

class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(savedConnectionsProvider);
    final connState = ref.watch(rpcConnectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AgentMux'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: connections.isEmpty
          ? _EmptyState(onAdd: () => context.push('/connections/add'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: connections.length,
              itemBuilder: (context, index) {
                final conn = connections[index];
                return _ConnectionCard(
                  connection: conn,
                  isConnected: connState.value == RpcConnectionState.connected &&
                      ref.read(activeConnectionProvider)?.id == conn.id,
                  onTap: () => _connect(context, ref, conn),
                  onDelete: () =>
                      ref.read(savedConnectionsProvider.notifier).remove(conn.id),
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'qr',
            onPressed: () {
              // TODO: QR scanner
            },
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => context.push('/connections/add'),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Future<void> _connect(
      BuildContext context, WidgetRef ref, ServerConnection conn) async {
    try {
      final connect = ref.read(connectActionProvider);
      await connect(conn);
      if (context.mounted) context.go('/sessions');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    }
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('No connections yet',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Add a connection to your AgentMux desktop',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Connection'),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final ServerConnection connection;
  final bool isConnected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConnectionCard({
    required this.connection,
    required this.isConnected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          isConnected ? Icons.cloud_done : Icons.cloud_off,
          color: isConnected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).textTheme.bodyMedium?.color,
        ),
        title: Text(connection.name),
        subtitle: Text(
          '${connection.host}:${connection.port}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        trailing: isConnected
            ? Chip(
                label: const Text('Connected'),
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                labelStyle:
                    TextStyle(color: Theme.of(context).colorScheme.primary),
              )
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
        onTap: onTap,
      ),
    );
  }
}

/// Add/edit connection form.
class AddConnectionScreen extends ConsumerStatefulWidget {
  const AddConnectionScreen({super.key});

  @override
  ConsumerState<AddConnectionScreen> createState() =>
      _AddConnectionScreenState();
}

class _AddConnectionScreenState extends ConsumerState<AddConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '1730');
  final _authKeyController = TextEditingController();
  bool _useTls = false;

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _authKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Connection')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hostController,
              decoration:
                  const InputDecoration(labelText: 'Host', hintText: '192.168.1.50'),
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _authKeyController,
              decoration: const InputDecoration(labelText: 'Auth Key'),
              obscureText: true,
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Use TLS'),
              subtitle: const Text('Required for remote connections'),
              value: _useTls,
              onChanged: (v) => setState(() => _useTls = v),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Save Connection'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final conn = ServerConnection(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 1730,
      authKey: _authKeyController.text,
      useTls: _useTls,
    );

    ref.read(savedConnectionsProvider.notifier).add(conn);
    context.pop();
  }
}
