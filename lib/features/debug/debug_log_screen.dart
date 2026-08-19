import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/discovery/discovery_telemetry.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/theme/app_theme.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  late List<LogEntry> _entries = AppLogger.entries;

  void _refresh() => setState(() => _entries = AppLogger.entries);

  Future<void> _copyAll() async {
    final text = _entries.map((e) => e.format()).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${_entries.length} log entries')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy all',
            onPressed: _entries.isEmpty ? null : _copyAll,
          ),
        ],
      ),
      body: Column(
        children: [
          const _SummaryHeader(),
          Expanded(
            child: _entries.isEmpty
                ? const Center(
                    child: Text(
                      // Was "Discovery/connection issues will show up here" —
                      // no longer accurate to imply that unconditionally: a
                      // clean discovery scan that finds nothing IS now logged
                      // (see the summary above), but plenty of other empty-log
                      // states are still perfectly normal (app just opened,
                      // nothing attempted yet). See
                      // docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md.
                      'No log entries yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (_, i) => _LogTile(entry: _entries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pinned summary of the most recent structured discovery telemetry —
/// network snapshot + last mDNS/UDP-broadcast scan outcome — so the big
/// picture doesn't require scrolling through free-text log lines to
/// reconstruct. Reads `DiscoveryTelemetry` directly (not `AppLogger`) since
/// this is the structured data those log lines are derived from. See
/// docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md.
class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader();

  @override
  Widget build(BuildContext context) {
    final snapshot = DiscoveryTelemetry.lastNetworkSnapshot;
    final mdns = DiscoveryTelemetry.lastMdnsSummary;
    final udp = DiscoveryTelemetry.lastUdpSummary;
    if (snapshot == null && mdns == null && udp == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppColors.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          const Text(
            'LAST DISCOVERY SCAN',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          if (snapshot != null)
            Text('Network: ${snapshot.format()}', style: _summaryStyle),
          if (snapshot?.hint != null)
            Text('⚠ ${snapshot!.hint}',
                style: _summaryStyle.copyWith(color: Colors.amber)),
          if (mdns != null) Text('mDNS: ${mdns.detail}', style: _summaryStyle),
          if (udp != null) Text('UDP broadcast: ${udp.detail}', style: _summaryStyle),
        ],
      ),
    );
  }

  static const _summaryStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 12,
  );
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              entry.name,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              entry.timestamp.toIso8601String(),
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          entry.message,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        ),
        if (entry.error != null) ...[
          const SizedBox(height: 4),
          Text(
            entry.error.toString(),
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
