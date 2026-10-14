import 'dart:convert';

import '../fleet/sse.dart';

/// One sample of a computer's counters, as its sysinfo loop takes them
/// (agentmux's `TimeSeriesData`: `GET /agentmux/viewer/sysinfo`, and each
/// `sample` event of `…/sysinfo/feed`). CPU in percent, memory in GB.
class SysinfoSample {
  const SysinfoSample({required this.ts, required this.values});

  /// When it was taken, ms since the epoch, on the computer's clock.
  final int ts;
  final Map<String, double> values;

  /// All cores' mean busy time, 0 to 100.
  double? get cpu => values['cpu'];

  /// Each core's, in core order.
  List<double> get cores {
    final out = <int, double>{};
    for (final e in values.entries) {
      if (!e.key.startsWith('cpu:')) continue;
      final i = int.tryParse(e.key.substring(4));
      if (i != null) out[i] = e.value;
    }
    final keys = out.keys.toList()..sort();
    return [for (final k in keys) out[k]!];
  }

  double? get memUsed => values['mem:used'];
  double? get memTotal => values['mem:total'];

  /// Memory in use, 0 to 100.
  double? get memPercent {
    final used = memUsed;
    final total = memTotal;
    if (used == null || total == null || total <= 0) return null;
    return used / total * 100;
  }

  /// One sample from its JSON, or null when it isn't one.
  static SysinfoSample? fromJson(Object? json) {
    if (json is! Map) return null;
    final ts = json['ts'];
    final raw = json['values'];
    if (ts is! num || raw is! Map) return null;
    final values = <String, double>{};
    for (final e in raw.entries.take(512)) {
      if (e.key is String && e.value is num && (e.value as num).isFinite) {
        values[e.key as String] = (e.value as num).toDouble();
      }
    }
    return SysinfoSample(ts: ts.toInt(), values: values);
  }
}

/// A `sample` event of the Sysinfo feed; null for anything else.
SysinfoSample? parseSysinfoEvent(SseEvent e) {
  if (e.event != 'sample') return null;
  try {
    return SysinfoSample.fromJson(jsonDecode(e.data));
  } on FormatException {
    return null;
  }
}
