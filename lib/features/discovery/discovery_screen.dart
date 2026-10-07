import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/discovery/discovery_provider.dart';
import '../../core/discovery/discovery_telemetry.dart';
import '../../core/discovery/host_tree.dart';
import '../../core/fleet/cloud_instance_source.dart';
import 'host_card.dart';
import 'manual_add_sheet.dart';
import 'qr_scan_screen.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(discoveryProvider);
    // Signing in or out changes what the cloud list may show; ask again now
    // rather than at its next 30 s tick.
    ref.listen(authProvider, (prev, next) {
      if (prev?.valueOrNull != next.valueOrNull) {
        ref.read(discoveryProvider.notifier).refreshCloud();
      }
    });

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
          // Cloud login/Demo/Settings/Debug consolidated into one overflow
          // menu rather than four more direct IconButtons. Even the
          // previous 5-control version (4 icons + this popup) still left
          // only ~64dp for the title on a 320dp iPhone SE per Codex review
          // on #28 — moving one more action in leaves 3 direct icons + 1
          // overflow trigger (~192dp), comfortably clearing room for
          // "AgentMux" at any supported width.
          PopupMenuButton<_MoreAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (action) => switch (action) {
              _MoreAction.cloudLogin => context.push('/login'),
              _MoreAction.demo => context.push('/demo'),
              _MoreAction.settings => context.push('/settings'),
              _MoreAction.debugLog => context.push('/debug-log'),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MoreAction.cloudLogin,
                child: ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('Cloud login'),
                ),
              ),
              PopupMenuItem(
                value: _MoreAction.demo,
                child: ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('View a demo fleet'),
                ),
              ),
              PopupMenuItem(
                value: _MoreAction.settings,
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                ),
              ),
              PopupMenuItem(
                value: _MoreAction.debugLog,
                child: ListTile(
                  leading: Icon(Icons.bug_report_outlined),
                  title: Text('Debug log'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: switch (state) {
        DiscoveryScanning() => const _ScanningView(),
        DiscoveryEmpty(:final cloud) => _EmptyView(cloud: cloud),
        DiscoveryResults(:final hosts, :final cloud) =>
          _ResultsView(hosts: hosts, cloud: cloud),
      },
    );
  }
}

enum _MoreAction { cloudLogin, demo, settings, debugLog }

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
  const _EmptyView({required this.cloud});
  final CloudListStatus cloud;

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
    final note = cloudNoteText(cloud);

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
          if (note != null) CloudNote(text: note),
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
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('View a demo fleet'),
            onPressed: () => context.push('/demo'),
          ),
        ],
      ),
    );
  }
}

class _ResultsView extends ConsumerWidget {
  const _ResultsView({required this.hosts, required this.cloud});
  final List<HostNode> hosts;
  final CloudListStatus cloud;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The list never implies it is everything (spec section 3.5).
    final note = cloudNoteText(cloud);
    return RefreshIndicator(
      onRefresh: () => ref.read(discoveryProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: hosts.length + (note == null ? 0 : 1),
        // Keyed by host so an update never hands one host's expanded state
        // to another.
        itemBuilder: (_, i) => i < hosts.length
            ? HostCard(key: ValueKey(hosts[i].key), host: hosts[i])
            : CloudNote(key: const ValueKey('cloud-note'), text: note!),
      ),
    );
  }
}
