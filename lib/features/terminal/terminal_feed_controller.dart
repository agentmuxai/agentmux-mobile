import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../core/fleet/channel_session.dart';
import '../../core/viewer/terminal_events.dart';
import '../../core/viewer/viewer_client.dart';

/// Opens the terminal feed, resuming after [lastEventId] when given.
typedef TerminalSource = Stream<TerminalEvent?> Function({String? lastEventId});

enum TerminalConnection {
  /// First connection, nothing received yet.
  connecting,
  live,

  /// The stream dropped; waiting to reconnect.
  reconnecting,

  /// The app is in the background: no stream.
  paused,

  /// The computer refused the token: this device was unpaired there.
  unauthorized,

  /// The terminal is gone, or belongs to an agent hidden from paired devices.
  notFound,

  /// The computer doesn't share its terminals (or stopped sharing them).
  notShared,
}

/// Keeps one terminal's live, read-only view: an xterm [Terminal] fed the
/// desktop's PTY bytes, sized as the desktop sized the PTY, and the
/// connection state. Nothing is ever sent to the terminal.
///
/// A dropped stream reconnects with full-jitter backoff and resumes after the
/// last byte shown (`Last-Event-ID`); bytes that don't follow on reconnect
/// without it, for a fresh snapshot. Bytes are decoded as one UTF-8 stream,
/// so a character split across two writes is kept whole.
class TerminalFeedController extends ChangeNotifier {
  TerminalFeedController({required this.source, this.onUnauthorized, Random? random})
      : _random = random ?? Random();

  final TerminalSource source;
  final VoidCallback? onUnauthorized;
  final Random _random;

  /// Lines kept above the screen.
  static const scrollback = 10000;

  /// A stream that stayed up this long resets the backoff.
  static const stableAfter = Duration(seconds: 30);

  TerminalConnection _connection = TerminalConnection.connecting;
  TerminalConnection get connection => _connection;

  Terminal? _terminal;

  /// Null until the first snapshot (and again right after a reset).
  Terminal? get terminal => _terminal;

  /// The size the desktop gave the PTY, once known: `(rows, cols)`.
  (int, int)? _size;
  (int, int)? get size => _size;

  ByteConversionSink? _decoder;
  int? _next;
  String? get lastEventId => _next?.toString();

  bool _disposed = false;
  bool _paused = false;
  int _run = 0;
  int _attempt = 0;
  Timer? _sleepTimer;
  Completer<void>? _sleep;
  StreamSubscription<TerminalEvent?>? _sub;

  void start() {
    if (_disposed || _paused) return;
    final run = ++_run;
    unawaited(_loop(run));
  }

  void pause() {
    if (_disposed || _paused || _ended) return;
    _paused = true;
    _run++;
    _endStream();
    _wake();
    _set(TerminalConnection.paused);
  }

  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _attempt = 0;
    _set(_terminal == null ? TerminalConnection.connecting : TerminalConnection.reconnecting);
    start();
  }

  /// The connection has ended for good.
  bool get _ended =>
      _connection == TerminalConnection.unauthorized ||
      _connection == TerminalConnection.notFound ||
      _connection == TerminalConnection.notShared;

  @override
  void dispose() {
    _disposed = true;
    _run++;
    _endStream();
    _wake();
    super.dispose();
  }

  void _set(TerminalConnection c) {
    if (_disposed || _connection == c) return;
    _connection = c;
    notifyListeners();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _endStream() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _wake() {
    _sleepTimer?.cancel();
    final s = _sleep;
    if (s != null && !s.isCompleted) s.complete();
  }

  Future<void> _wait(Duration d) {
    final c = Completer<void>();
    _sleep = c;
    _sleepTimer = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  Future<void> _loop(int run) async {
    while (run == _run) {
      TerminalConnection? end;
      try {
        end = await _streamOnce(run);
      } on ViewerUnauthorized {
        end = TerminalConnection.unauthorized;
      } on ViewerNotFound {
        end = TerminalConnection.notFound;
      } on ViewerForbidden {
        end = TerminalConnection.notShared;
      } catch (_) {
        // Any other failure is a lost connection: back off and retry.
      }
      if (run != _run) return;
      if (end != null) {
        _run++;
        _set(end);
        if (end == TerminalConnection.unauthorized) onUnauthorized?.call();
        return;
      }
      _set(TerminalConnection.reconnecting);
      await _wait(fullJitterBackoff(_attempt++, _random));
    }
  }

  /// One connection. Returns how the feed ended for good, or null to retry.
  Future<TerminalConnection?> _streamOnce(int run) async {
    final done = Completer<TerminalConnection?>();
    DateTime? connectedAt;
    _sub = source(lastEventId: lastEventId).listen(
      (event) {
        if (run != _run) return;
        connectedAt ??= clock.now();
        _set(TerminalConnection.live);
        if (event != null) _apply(event, done);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(null);
      },
      cancelOnError: true,
    );
    try {
      return await done.future;
    } finally {
      _sub = null;
      final up = connectedAt;
      if (up != null && clock.now().difference(up) >= stableAfter) _attempt = 0;
    }
  }

  void _apply(TerminalEvent event, Completer<TerminalConnection?> done) {
    switch (event) {
      case TerminalSnapshot():
        final terminal = Terminal(maxLines: scrollback);
        final rows = event.rows;
        final cols = event.cols;
        if (rows != null && cols != null) {
          _size = (rows, cols);
          terminal.resize(cols, rows);
        } else if (_size case (final r, final c)) {
          terminal.resize(c, r);
        }
        _terminal = terminal;
        _decoder = _decoderFor(terminal);
        _decoder!.add(event.data);
        _next = event.nextOffset;
        _changed();
      case TerminalAppend():
        final next = _next;
        final decoder = _decoder;
        if (next == null || decoder == null) return _resync(done);
        final end = event.offset + event.data.length;
        if (end <= next) return;
        if (event.offset > next) return _resync(done);
        decoder.add(event.data.sublist(next - event.offset));
        _next = end;
        _changed();
      case TerminalResize():
        _size = (event.rows, event.cols);
        _terminal?.resize(event.cols, event.rows);
        _changed();
      case TerminalReset(:final reason):
        _terminal = null;
        _decoder = null;
        _next = null;
        _changed();
        // The stream ends after these; nothing to retry.
        final end = switch (reason) {
          'not_shared' => TerminalConnection.notShared,
          'hidden' || 'gone' => TerminalConnection.notFound,
          _ => null,
        };
        if (end != null && !done.isCompleted) done.complete(end);
    }
  }

  static ByteConversionSink _decoderFor(Terminal terminal) =>
      const Utf8Decoder(allowMalformed: true)
          .startChunkedConversion(_TerminalSink(terminal));

  /// Drops the resume point and ends the stream: the loop reconnects and gets
  /// a fresh snapshot.
  void _resync(Completer<TerminalConnection?> done) {
    _next = null;
    unawaited(_sub?.cancel());
    _sub = null;
    if (!done.isCompleted) done.complete(null);
  }
}

class _TerminalSink implements Sink<String> {
  _TerminalSink(this._terminal);
  final Terminal _terminal;

  @override
  void add(String data) => _terminal.write(data);

  @override
  void close() {}
}
