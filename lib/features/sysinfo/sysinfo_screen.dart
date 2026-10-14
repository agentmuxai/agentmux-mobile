import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/viewer/paired_host.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/sysinfo_events.dart';
import '../../core/viewer/viewer_client.dart';
import '../../shared/theme/app_theme.dart';

/// A paired computer's CPU and memory, live
/// (`PLAN_CHANNEL_AS_ONE_LIST_2026_10_13.md` step 3b): the last few minutes
/// as charts, and each core under a tap. Read-only; kept in memory only, and
/// paused while the app is in the background.
class SysinfoScreen extends ConsumerStatefulWidget {
  const SysinfoScreen({super.key, required this.pairing});
  final PairingMatch pairing;

  @override
  ConsumerState<SysinfoScreen> createState() => _SysinfoScreenState();
}

enum SysinfoConnection { connecting, live, reconnecting, tooOld, unpaired }

/// How far back the charts reach.
const sysinfoWindow = Duration(minutes: 5);

class _SysinfoScreenState extends ConsumerState<SysinfoScreen> {
  final _samples = <SysinfoSample>[];
  SysinfoConnection _connection = SysinfoConnection.connecting;
  ViewerClient? _client;
  StreamSubscription<SysinfoSample?>? _sub;
  Timer? _retry;
  AppLifecycleListener? _lifecycle;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _paused = true;
        _close();
      },
      onResume: () {
        _paused = false;
        _open();
      },
    );
    _open();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _close();
    super.dispose();
  }

  void _close() {
    _retry?.cancel();
    _retry = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _client?.close();
    _client = null;
  }

  void _open() {
    _close();
    if (_paused) return;
    final paired = widget.pairing.paired;
    if (paired.invalid) {
      setState(() => _connection = SysinfoConnection.unpaired);
      return;
    }
    final client = ref.read(viewerClientFactoryProvider)(
      host: widget.pairing.host,
      port: widget.pairing.port,
      fingerprint: paired.fingerprint,
      token: paired.token,
    );
    _client = client;
    // A reconnect resumes after the last sample it has.
    final since = _samples.isEmpty ? null : _samples.last.ts;
    _sub = client.sysinfoFeed(since: since).listen(
      (sample) {
        if (!mounted) return;
        setState(() {
          _connection = SysinfoConnection.live;
          if (sample != null) addSample(_samples, sample);
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        if (e is ViewerNotFound) {
          setState(() => _connection = SysinfoConnection.tooOld);
          _close();
          return;
        }
        if (e is ViewerUnauthorized) {
          unawaited(ref.read(pairedHostsProvider.notifier).markInvalid(paired.id));
          setState(() => _connection = SysinfoConnection.unpaired);
          _close();
          return;
        }
        _reconnectSoon();
      },
      onDone: _reconnectSoon,
      cancelOnError: true,
    );
  }

  void _reconnectSoon() {
    if (!mounted || _paused) return;
    setState(() => _connection = SysinfoConnection.reconnecting);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), _open);
  }

  @override
  Widget build(BuildContext context) {
    final latest = _samples.lastOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sysinfo'),
            Text(
              widget.pairing.paired.hostname,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [_ConnectionChip(_connection)],
      ),
      body: switch (_connection) {
        SysinfoConnection.tooOld => const _Message('Update AgentMux on the computer to see its Sysinfo here.'),
        SysinfoConnection.unpaired => const _Message('This device was unpaired on the computer.'),
        _ when latest == null => const Center(child: CircularProgressIndicator()),
        _ => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _ChartCard(
                title: 'CPU',
                value: latest.cpu == null ? '—' : '${latest.cpu!.round()}%',
                detail: '${latest.cores.length} cores',
                points: [for (final s in _samples) s.cpu],
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              _ChartCard(
                title: 'Memory',
                value: latest.memPercent == null ? '—' : '${latest.memPercent!.round()}%',
                detail: latest.memUsed == null || latest.memTotal == null
                    ? ''
                    : '${latest.memUsed!.toStringAsFixed(1)} of ${latest.memTotal!.toStringAsFixed(1)} GB',
                points: [for (final s in _samples) s.memPercent],
                color: AppColors.success,
              ),
              const SizedBox(height: 12),
              if (latest.cores.isNotEmpty) _Cores(latest.cores),
            ],
          ),
      },
    );
  }
}

/// How far back a sample's time can jump before it means the computer's
/// clock was set back, rather than a sample this device already has.
const clockStepBack = Duration(seconds: 10);

/// Adds [sample] to [samples] in time order, once, keeping [sysinfoWindow].
/// A sample far older than the last means the computer's clock went back:
/// the chart starts again from it.
void addSample(List<SysinfoSample> samples, SysinfoSample sample) {
  if (samples.isNotEmpty && sample.ts <= samples.last.ts) {
    if (samples.last.ts - sample.ts < clockStepBack.inMilliseconds) return;
    samples.clear();
  }
  samples.add(sample);
  final from = sample.ts - sysinfoWindow.inMilliseconds;
  samples.removeWhere((s) => s.ts < from);
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip(this.connection);
  final SysinfoConnection connection;

  @override
  Widget build(BuildContext context) {
    final (String, Color)? shown = switch (connection) {
      SysinfoConnection.live => ('Live', AppColors.success),
      SysinfoConnection.connecting => ('Connecting…', AppColors.warning),
      SysinfoConnection.reconnecting => ('Reconnecting…', AppColors.warning),
      _ => null,
    };
    if (shown == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: shown.$2),
          const SizedBox(width: 6),
          Text(shown.$1, style: TextStyle(fontSize: 12, color: shown.$2)),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.points,
    required this.color,
  });
  final String title;
  final String value;
  final String detail;
  final List<double?> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(width: 8),
                Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: color)),
                const Spacer(),
                Text(detail, style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: CustomPaint(
                painter: PercentChartPainter(points: points, color: color),
              ),
            ),
            const SizedBox(height: 4),
            const Text('last 5 minutes', style: TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

/// A 0–100 line over time, oldest at the left; a missing value breaks it.
class PercentChartPainter extends CustomPainter {
  PercentChartPainter({required this.points, required this.color});
  final List<double?> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2) return;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dx = size.width / (points.length - 1);
    Path? path;
    for (var i = 0; i < points.length; i++) {
      final v = points[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      final p = Offset(i * dx, size.height * (1 - v.clamp(0, 100) / 100));
      if (path == null) {
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (path != null) canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(PercentChartPainter old) => old.points != points || old.color != color;
}

/// Each core's busy time now, under a tap.
class _Cores extends StatelessWidget {
  const _Cores(this.cores);
  final List<double> cores;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('${cores.length} cores', style: const TextStyle(fontSize: 14)),
        children: [
          for (final (i, v) in cores.indexed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('$i', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (v / 100).clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text('${v.round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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
