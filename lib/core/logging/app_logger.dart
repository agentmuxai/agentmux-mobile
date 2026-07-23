import 'dart:collection';
import 'dart:developer' as developer;

class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.name,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final String name;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  String format() {
    final buf = StringBuffer()
      ..write('${timestamp.toIso8601String()} [$name] $message');
    if (error != null) buf.write('\n  error: $error');
    if (stackTrace != null) buf.write('\n$stackTrace');
    return buf.toString();
  }
}

/// Thin wrapper around `dart:developer.log` that also retains the last
/// [_maxEntries] entries in memory so they're readable from within the app
/// (see DebugLogScreen) — not just from an attached debug session.
class AppLogger {
  AppLogger._();

  static const _maxEntries = 200;
  static final Queue<LogEntry> _entries = Queue<LogEntry>();

  static List<LogEntry> get entries => List.unmodifiable(_entries);

  static void log(
    String message, {
    required String name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      name: name,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
    _entries.addFirst(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    developer.log(message, name: name, error: error, stackTrace: stackTrace);
  }

  static void clear() => _entries.clear();
}
