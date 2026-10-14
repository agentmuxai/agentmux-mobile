/// A computer's Tower, as `GET /agentmux/viewer/procs` sends it to a paired
/// device (agentmux's `TowerSnapshot`): its tasks (each agent and terminal
/// pane, and AgentMux itself, with what they started), its totals, and its
/// busiest and largest processes, names only. CPU is a fraction of one core;
/// memory is bytes.
class TowerSnapshot {
  const TowerSnapshot({
    required this.cpuCount,
    required this.intervalMs,
    required this.tasks,
    this.machine,
    this.host,
  });

  final int cpuCount;

  /// How often the desktop suggests asking again.
  final int intervalMs;
  final List<TowerTask> tasks;
  final TowerMachine? machine;
  final TowerHost? host;

  /// [cores] (a fraction of one core) as a percent of the whole machine.
  double percentOfMachine(double cores) => cpuCount <= 0 ? cores * 100 : cores / cpuCount * 100;

  static TowerSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final tasks = json['tasks'];
    return TowerSnapshot(
      cpuCount: _int(json['cpu_count']) ?? 0,
      intervalMs: _int(json['interval_ms']) ?? 2000,
      tasks: [
        if (tasks is List)
          for (final t in tasks.take(500))
            if (TowerTask.fromJson(t) case final task?) task,
      ],
      machine: TowerMachine.fromJson(json['machine']),
      host: TowerHost.fromJson(json['host']),
    );
  }
}

enum TowerTaskKind { agent, terminal, agentmux }

/// A pane and every process it started, or AgentMux itself.
class TowerTask {
  const TowerTask({
    required this.id,
    required this.kind,
    required this.label,
    required this.mem,
    required this.processes,
    this.cpu,
  });
  final String id;
  final TowerTaskKind kind;
  final String label;
  final double? cpu;
  final int mem;
  final List<TowerProcess> processes;

  static TowerTask? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final kind = switch (json['kind']) {
      'agent' => TowerTaskKind.agent,
      'terminal' => TowerTaskKind.terminal,
      'agentmux' => TowerTaskKind.agentmux,
      _ => null,
    };
    if (id is! String || kind == null) return null;
    final procs = json['processes'];
    return TowerTask(
      id: id,
      kind: kind,
      label: json['label'] is String ? json['label'] as String : '',
      cpu: _double(json['cpu']),
      mem: _int(json['mem']) ?? 0,
      processes: [
        if (procs is List)
          for (final p in procs.take(500))
            if (TowerProcess.fromJson(p) case final proc?) proc,
      ],
    );
  }
}

/// The machine's totals.
class TowerMachine {
  const TowerMachine({required this.mem, required this.processes, this.cpu});
  final double? cpu;
  final int mem;
  final int processes;

  static TowerMachine? fromJson(Object? json) {
    if (json is! Map) return null;
    return TowerMachine(
      cpu: _double(json['cpu']),
      mem: _int(json['mem']) ?? 0,
      processes: _int(json['processes']) ?? 0,
    );
  }
}

/// The machine's busiest and largest processes (of [matched] matching the
/// filter, of [total]).
class TowerHost {
  const TowerHost({required this.processes, required this.total, required this.matched});
  final List<TowerProcess> processes;
  final int total;
  final int matched;

  static TowerHost? fromJson(Object? json) {
    if (json is! Map) return null;
    final procs = json['processes'];
    return TowerHost(
      processes: [
        if (procs is List)
          for (final p in procs.take(1000))
            if (TowerProcess.fromJson(p) case final proc?) proc,
      ],
      total: _int(json['total']) ?? 0,
      matched: _int(json['matched']) ?? 0,
    );
  }
}

/// One process: a name and PID, never a command line.
class TowerProcess {
  const TowerProcess({required this.pid, required this.name, this.cpu, this.mem, this.detail});
  final int pid;
  final String name;
  final double? cpu;
  final int? mem;

  /// For one of AgentMux's own: what it is ("Server", "Renderer", …).
  final String? detail;

  static TowerProcess? fromJson(Object? json) {
    if (json is! Map) return null;
    final pid = _int(json['pid']);
    final name = json['name'];
    if (pid == null || name is! String) return null;
    final detail = json['detail'];
    return TowerProcess(
      pid: pid,
      name: name.length > 200 ? name.substring(0, 200) : name,
      cpu: _double(json['cpu']),
      mem: _int(json['mem']),
      detail: detail is String ? detail : null,
    );
  }
}

int? _int(Object? v) => v is num && v.isFinite ? v.toInt() : null;
double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

/// `812 MB`, `9.8 GB`.
String formatMemory(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).round()} KB';
}
