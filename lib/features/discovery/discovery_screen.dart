import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/discovery_provider.dart';
import '../../core/discovery/models/lan_instance.dart';
import 'instance_card.dart';
import 'manual_add_sheet.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(discoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AgentMux'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(discoveryProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Connect manually',
            onPressed: () => showManualAddSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Cloud login',
            onPressed: () => context.push('/login'),
          ),
        ],
      ),
      body: state.when(
        loading: () => const _ScanningView(),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (s) => switch (s) {
          DiscoveryScanning() => const _ScanningView(),
          DiscoveryEmpty() => const _EmptyView(),
          DiscoveryResults(:final instances) =>
            _ResultsView(instances: instances),
          DiscoveryError(:final message) => _ErrorView(message: message),
        },
      ),
    );
  }
}

class _ScanningView extends StatelessWidget {
  const _ScanningView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'Searching for AgentMux\non your network…',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.white38),
          const SizedBox(height: 24),
          const Text(
            'No AgentMux found on this network.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Make sure LAN discovery is enabled\non your desktop instance.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Connect manually'),
            onPressed: () => showManualAddSheet(context),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.cloud),
            label: const Text('Sign in to cloud →'),
            onPressed: () => context.push('/login'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Discovery error: $message',
        style: const TextStyle(color: Colors.redAccent),
      ),
    );
  }
}

class _ResultsView extends ConsumerWidget {
  const _ResultsView({required this.instances});
  final List<LanInstance> instances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(discoveryProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: instances.length,
        itemBuilder: (_, i) => InstanceCard(instance: instances[i]),
      ),
    );
  }
}
