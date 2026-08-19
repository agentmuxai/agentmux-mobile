import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/discovery_provider.dart';
import '../../core/discovery/discovery_telemetry.dart';
import '../../core/discovery/models/lan_instance.dart';
import 'instance_card.dart';
import 'manual_add_sheet.dart';
import 'qr_scan_screen.dart';

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
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR code',
            onPressed: () => showQrScanScreen(context),
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
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug log',
            onPressed: () => context.push('/debug-log'),
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
    // Non-blocking hint from the network snapshot captured at scan start —
    // e.g. "this looks like the Android emulator's isolated NAT networking,
    // not a bug." Answers "why isn't anything showing up" in-app instead of
    // requiring the debug log / external network inspection. Null (no
    // banner) when the snapshot didn't match a known-unfriendly pattern —
    // that does NOT mean discovery will succeed, only that this specific
    // check didn't find anything obviously wrong. See
    // docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md.
    final hint = DiscoveryTelemetry.lastNetworkSnapshot?.hint;

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
          if (hint != null) ...[
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
            onPressed: () => showQrScanScreen(context),
          ),
          const SizedBox(height: 12),
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
