import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/discovery/discovery_provider.dart';
import '../../core/discovery/discovery_telemetry.dart';
import '../../core/discovery/host_tree.dart';
import '../../core/fleet/cloud_instance_source.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/adaptive.dart';
import '../../shared/widgets/edge_insets.dart';
import '../sysinfo/sysinfo_summary.dart';
import '../tower/tower_screen.dart';
import '../welcome/welcome.dart';
import 'channel_terminals.dart';
import 'host_card.dart';
import 'manual_add_sheet.dart';
import 'muxbus_account_bar.dart';
import 'qr_scan_screen.dart';

/// For a phone on the same network as the computer that still finds nothing.
const lanDiscoveryHint =
    'On the same Wi-Fi? Make sure LAN discovery is on in AgentMux on your '
    'computer.';

/// The app's first screen. On the first launch it is the welcome page, and
/// the search of the network starts only once the person has moved on from
/// it; from then on it is the list of computers.
class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(welcomeSeenProvider)) {
      AsyncData(value: false) => const WelcomeScreen(),
      AsyncData() || AsyncError() => const _Computers(),
      // Reading whether the welcome was shown: a moment, with nothing drawn.
      _ => Scaffold(backgroundColor: context.palette.background),
    };
  }
}

class _Computers extends ConsumerWidget {
  const _Computers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(discoveryProvider);
    final compactBar =
        MediaQuery.sizeOf(context).width < 360 || isLargeText(context);
    void refresh() {
      ref.invalidate(channelPanesProvider);
      ref.invalidate(channelSysinfoProvider);
      ref.invalidate(channelTowerProvider);
      ref.read(discoveryProvider.notifier).refresh();
    }

    // Signing in or out changes what the cloud list may show; ask again now
    // rather than at its next 30 s tick.
    ref.listen(authProvider, (prev, next) {
      if (prev?.valueOrNull != next.valueOrNull) {
        ref.read(discoveryProvider.notifier).refreshCloud();
      }
    });

    return Scaffold(
      appBar: AppBarInset(child: AppBar(
        // The title is chrome: at a large text size it took what the icons
        // need, and read "Agen…" (A6).
        title: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: const Text('AgentMux'),
        ),
        actions: [
          // Refresh moves into the menu where the four buttons would leave the
          // title no room: a window under 360 dp wide, or large text.
          if (!compactBar)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: refresh,
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
          // Demo/Settings/Debug consolidated into one overflow menu rather
          // than more direct IconButtons: 3 direct icons + 1 overflow
          // trigger (~192dp) leaves room for "AgentMux" on a 320dp screen
          // (Codex review on #28). MuxBus sign-in is not in here: it is the
          // always-visible button at the bottom (MuxbusAccountBar).
          PopupMenuButton<_MoreAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (action) => switch (action) {
              _MoreAction.refresh => refresh(),
              _MoreAction.demo => context.push('/demo'),
              _MoreAction.settings => context.push('/settings'),
              _MoreAction.debugLog => context.push('/debug-log'),
            },
            itemBuilder: (context) => [
              if (compactBar)
                const PopupMenuItem(
                  value: _MoreAction.refresh,
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Refresh'),
                  ),
                ),
              const PopupMenuItem(
                value: _MoreAction.demo,
                child: ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('View a demo fleet'),
                ),
              ),
              const PopupMenuItem(
                value: _MoreAction.settings,
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                ),
              ),
              const PopupMenuItem(
                value: _MoreAction.debugLog,
                child: ListTile(
                  leading: Icon(Icons.bug_report_outlined),
                  title: Text('Debug log'),
                ),
              ),
            ],
          ),
        ],
      )),
      body: ContentWidth(child: switch (state) {
        DiscoveryScanning() => const _ScanningView(),
        DiscoveryEmpty(:final cloud) => _EmptyView(cloud: cloud),
        DiscoveryResults(:final hosts, :final cloud) =>
          _ResultsView(hosts: hosts, cloud: cloud),
      }),
      // Always on screen, outside the scrolling list.
      bottomNavigationBar: const MuxbusAccountBar(),
    );
  }
}

enum _MoreAction { refresh, demo, settings, debugLog }

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

    // Scrolls when it can't fit (a small screen, large text, the footer
    // button below it).
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 48, color: context.palette.textFaint),
            const SizedBox(height: 16),
            const Text(
              'No AgentMux instances found on this network',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                whatAgentMuxIs,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.textDim, fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            // The offer: with nothing connected, the QR code is the way in
            // that always works (another network, discovery off, a firewall).
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      key: const ValueKey('scan-offer'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.palette.surface,
                        border: Border.all(color: context.palette.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Connect a computer',
                            style: TextStyle(
                              color: context.palette.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            whereTheQrCodeIs,
                            style: TextStyle(
                              color: context.palette.textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            icon: const Icon(Icons.qr_code_scanner, size: 20),
                            label: const Text('Scan QR code'),
                            onPressed: () => showQrScanScreen(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Connect manually'),
                      onPressed: () => showManualAddSheet(context),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      lanDiscoveryHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.palette.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.palette.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: context.palette.warning.withValues(alpha: 0.4)),
                ),
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.warning, fontSize: 12),
                ),
              ),
            ],
            if (note != null) CloudNote(text: note),
            const SizedBox(height: 4),
            TextButton.icon(
              icon: const Icon(Icons.visibility_outlined, size: 20),
              label: const Text('View a demo fleet'),
              onPressed: () => context.push('/demo'),
            ),
          ],
        ),
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
      onRefresh: () {
        // A paired channel's terminals are read again too.
        ref.invalidate(channelPanesProvider);
        ref.invalidate(channelSysinfoProvider);
        ref.invalidate(channelTowerProvider);
        return ref.read(discoveryProvider.notifier).refresh();
      },
      child: ListView.builder(
        padding: insetListPadding(context, const EdgeInsets.all(12)),
        itemCount: hosts.length + (note == null ? 0 : 1),
        // Keyed by host so an update never hands one host's expanded state
        // to another.
        itemBuilder: (_, i) => i < hosts.length
            ? HostCard(
                key: ValueKey(hosts[i].key),
                host: hosts[i],
                onUnpair: (paired) {
                  ref.read(pairedHostsProvider.notifier).remove(paired.id);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Unpaired ${paired.hostname}'),
                  ));
                },
              )
            : CloudNote(key: const ValueKey('cloud-note'), text: note!),
      ),
    );
  }
}
