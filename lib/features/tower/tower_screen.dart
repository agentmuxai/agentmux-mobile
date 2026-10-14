import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/viewer/paired_host.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/tower_snapshot.dart';
import '../../core/viewer/viewer_client.dart';
import '../discovery/channel_terminals.dart' show PanesKey;

/// What the channel list says on a paired computer's Tower row.
sealed class TowerSummary {
  const TowerSummary();
}

class TowerNow extends TowerSummary {
  const TowerNow(this.snapshot);
  final TowerSnapshot snapshot;
}

/// The computer doesn't share its processes (403).
class TowerNotShared extends TowerSummary {
  const TowerNotShared();
}

class TowerTooOld extends TowerSummary {
  const TowerTooOld();
}

class TowerUnreachable extends TowerSummary {
  const TowerUnreachable();
}

/// The desktop's own words for the setting, in Tower's menu.
const towerShareSetting = "Share this computer's processes with paired devices";

/// A paired computer's Tower, for its row (`PLAN_CHANNEL_AS_ONE_LIST_2026_10_13.md`
/// step 4). Read when the row shows, and again on refresh.
final channelTowerProvider = FutureProvider.autoDispose.family<TowerSummary, PanesKey>((ref, key) async {
  final hosts = ref.read(pairedHostsProvider);
  final paired = hosts.where((h) => h.id == key.pairId).firstOrNull;
  if (paired == null || paired.invalid) return const TowerUnreachable();
  final client = ref.read(viewerClientFactoryProvider)(
    host: key.host,
    port: key.port,
    fingerprint: paired.fingerprint,
    token: paired.token,
  );
  try {
    return TowerNow(await client.procs());
  } on ViewerForbidden {
    return const TowerNotShared();
  } on ViewerNotFound {
    return const TowerTooOld();
  } catch (_) {
    return const TowerUnreachable();
  } finally {
    client.close();
  }
});

/// "142 processes".
String towerSummaryText(TowerSummary? s) => switch (s) {
      null => '',
      TowerNow(:final snapshot) => () {
          final n = snapshot.machine?.processes ?? snapshot.host?.total;
          return n == null ? '' : '$n ${n == 1 ? 'process' : 'processes'}';
        }(),
      TowerNotShared() => 'Not shared',
      TowerTooOld() => 'Needs a newer AgentMux',
      TowerUnreachable() => "Can't reach it",
    };

/// A paired computer's Tower, read-only (step 4): its totals, each task (an
/// agent or terminal pane and what it started, or AgentMux itself), and its
/// busiest and largest processes, names only. Refreshed every few seconds
/// while open, paused in the background.
class TowerScreen extends ConsumerStatefulWidget {
  const TowerScreen({super.key, required this.pairing});
  final PairingMatch pairing;

  @override
  ConsumerState<TowerScreen> createState() => _TowerScreenState();
}

class _TowerScreenState extends ConsumerState<TowerScreen> {
  TowerSummary? _state;
  Timer? _timer;
  bool _paused = false;
  bool _loading = false;
  String _filter = '';
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _paused = true;
        _timer?.cancel();
      },
      onResume: () {
        _paused = false;
        unawaited(_load());
      },
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || _paused) return;
    _timer?.cancel();
    final paired = widget.pairing.paired;
    _loading = true;
    final client = ref.read(viewerClientFactoryProvider)(
      host: widget.pairing.host,
      port: widget.pairing.port,
      fingerprint: paired.fingerprint,
      token: paired.token,
    );
    TowerSummary next;
    try {
      next = TowerNow(await client.procs(filter: _filter));
    } on ViewerForbidden {
      next = const TowerNotShared();
    } on ViewerNotFound {
      next = const TowerTooOld();
    } on ViewerUnauthorized {
      unawaited(ref.read(pairedHostsProvider.notifier).markInvalid(paired.id));
      next = const TowerUnreachable();
    } catch (_) {
      next = const TowerUnreachable();
    } finally {
      client.close();
      _loading = false;
    }
    if (!mounted) return;
    setState(() => _state = next);
    // Sharing can be turned on while the screen is open: keep asking.
    final every = next is TowerNow ? next.snapshot.intervalMs.clamp(2000, 10000) : 5000;
    if (!_paused) _timer = Timer(Duration(milliseconds: every), () => unawaited(_load()));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tower'),
            Text(
              widget.pairing.paired.hostname,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: switch (state) {
        null => const Center(child: CircularProgressIndicator()),
        TowerNotShared() => const _Message(
            "This computer doesn't share its processes.\n\n"
            'On the computer, turn on "$towerShareSetting" in Tower\'s menu.',
          ),
        TowerTooOld() => const _Message('Update AgentMux on the computer to see its Tower here.'),
        TowerUnreachable() => const _Message("Can't reach the computer. Retrying…"),
        TowerNow(:final snapshot) => _Snapshot(
            snapshot: snapshot,
            onFilter: (f) {
              _filter = f;
              unawaited(_load());
            },
          ),
      },
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.snapshot, required this.onFilter});
  final TowerSnapshot snapshot;
  final ValueChanged<String> onFilter;

  String _cpu(double? cores) => cores == null ? '—' : '${snapshot.percentOfMachine(cores).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final m = snapshot.machine;
    final host = snapshot.host;
    final busiest = [...?host?.processes]..sort((a, b) => (b.cpu ?? -1).compareTo(a.cpu ?? -1));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (m != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'CPU ${_cpu(m.cpu)} · ${formatMemory(m.mem)} in ${m.processes} processes · ${snapshot.cpuCount} cores',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
        const _Heading('Tasks'),
        for (final t in snapshot.tasks)
          ExpansionTile(
            key: ValueKey('task:${t.id}'),
            dense: true,
            leading: Icon(
              switch (t.kind) {
                TowerTaskKind.agent => Icons.smart_toy_outlined,
                TowerTaskKind.terminal => Icons.terminal,
                TowerTaskKind.agentmux => Icons.widgets_outlined,
              },
              size: 18,
            ),
            title: Text(t.label.isEmpty ? 'AgentMux' : t.label, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${_cpu(t.cpu)} · ${formatMemory(t.mem)} · ${t.processes.length} '
              '${t.processes.length == 1 ? 'process' : 'processes'}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            children: [for (final p in t.processes) _ProcessRow(p, cpu: _cpu(p.cpu))],
          ),
        const _Heading('Busiest and largest'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Filter by name or PID',
            ),
            onSubmitted: onFilter,
          ),
        ),
        if (host != null && host.matched != host.total)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              '${host.matched} of ${host.total} match',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
        for (final p in busiest) _ProcessRow(p, cpu: _cpu(p.cpu)),
      ],
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow(this.p, {required this.cpu});
  final TowerProcess p;
  final String cpu;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        p.detail == null ? p.name : '${p.name} · ${p.detail}',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text('PID ${p.pid}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
      trailing: Text(
        '$cpu · ${p.mem == null ? '—' : formatMemory(p.mem!)}',
        style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ),
      );
}
