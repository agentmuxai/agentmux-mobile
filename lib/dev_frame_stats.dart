// Dev only: logs how long frames take, for measuring scrolling and streaming
// in a profile build (Android's `gfxinfo` sees nothing of a Flutter surface).
//
//   flutter build apk --profile -t lib/dev_pair_main.dart --dart-define=AGENTMUX_FRAME_STATS=true
//   adb logcat -s flutter:I | grep frame-stats
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

const _enabled = bool.fromEnvironment('AGENTMUX_FRAME_STATS');

/// Every 5 s with frames to report: the count, the build (UI thread) and
/// raster times at the median, 90th and 99th percentile and the slowest, and
/// how many frames missed 16.7 ms (60 Hz).
void startFrameStats() {
  if (!_enabled) return;
  final build = <int>[];
  final raster = <int>[];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
  });
  Timer.periodic(const Duration(seconds: 5), (_) {
    if (build.isEmpty) return;
    String line(String name, List<int> us) {
      final s = [...us]..sort();
      double ms(double q) => s[((s.length - 1) * q).round()] / 1000;
      return '$name p50=${ms(0.5).toStringAsFixed(1)} p90=${ms(0.9).toStringAsFixed(1)} '
          'p99=${ms(0.99).toStringAsFixed(1)} max=${(s.last / 1000).toStringAsFixed(1)}';
    }

    final slow = [
      for (var i = 0; i < build.length; i++)
        if (build[i] + raster[i] > 16700) 1,
    ].length;
    debugPrint('frame-stats: frames=${build.length} slow=$slow ms: ${line('build', build)} | ${line('raster', raster)}');
    build.clear();
    raster.clear();
  });
}
