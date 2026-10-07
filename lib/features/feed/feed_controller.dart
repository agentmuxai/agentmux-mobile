import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../core/fleet/channel_session.dart';
import '../../core/viewer/feed_events.dart';
import '../../core/viewer/viewer_client.dart';
import 'transcript.dart';

/// Opens the feed stream, resuming after [lastEventId] when given. See
/// `ViewerClient.feed` for what it emits.
typedef FeedSource = Stream<FeedEvent?> Function({String? lastEventId});

enum FeedConnection {
  /// First connection, nothing received yet.
  connecting,
  live,

  /// The stream dropped; waiting to reconnect.
  reconnecting,

  /// The app is in the background: no stream, no battery or data use.
  paused,

  /// The computer refused the token: this device was unpaired there.
  unauthorized,

  /// The agent is unknown on the computer or hidden from paired devices.
  notFound,
}

/// Keeps one agent's live feed (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md`
/// 5, 6.2 and 13.3) for the feed screen: the transcript, the agent's latest
/// status and the connection state.
///
/// A dropped stream reconnects with full-jitter backoff and resumes with
/// `Last-Event-ID`, so nothing is shown twice or skipped; an append that does
/// not follow on (another generation, or a gap) reconnects without it and
/// gets a fresh snapshot. A 401 stops for good ([onUnauthorized]). Content
/// lives in memory only. Timing reads `clock` and `Timer`, so tests drive it
/// with `fake_async`.
class FeedController extends ChangeNotifier {
  FeedController({
    required this.source,
    this.onUnauthorized,
    Random? random,
  }) : _random = random ?? Random();

  final FeedSource source;
  final VoidCallback? onUnauthorized;
  final Random _random;

  /// A stream that stayed up this long resets the backoff.
  static const stableAfter = Duration(seconds: 30);

  FeedConnection _connection = FeedConnection.connecting;
  FeedConnection get connection => _connection;

  Transcript? _transcript;

  /// Null until the first snapshot (and again right after a `reset`).
  Transcript? get transcript => _transcript;

  FeedStatus? _status;
  DateTime? _statusAt;

  /// The agent's latest state from `status` events, for the header's chip;
  /// null until the first one.
  FeedStatus? get status => _status;

  /// This device's clock when [status] arrived: its `now_ms - since_ms` is
  /// anchored there, so the desktop's clock is never compared with ours.
  DateTime? get statusReceivedAt => _statusAt;

  String? _gen;
  int? _nextLine;
  String? _lastEventId;

  /// Where a reconnect resumes: `<gen>:<next line>`.
  String? get lastEventId => _lastEventId;

  bool _disposed = false;
  bool _paused = false;

  /// Bumped by every start, pause and dispose; a loop or stream from an
  /// older run sees the change and stops touching state.
  int _run = 0;
  int _attempt = 0;
  Timer? _sleepTimer;
  Completer<void>? _sleep;
  StreamSubscription<FeedEvent?>? _sub;
  Completer<void>? _streamDone;

  void start() {
    if (_disposed || _paused) return;
    final run = ++_run;
    unawaited(_loop(run));
  }

  /// The app went to the background: the stream is closed, what was shown
  /// stays.
  void pause() {
    if (_disposed || _paused || _terminal) return;
    _paused = true;
    _run++;
    _endStream();
    _wake();
    _set(FeedConnection.paused);
  }

  /// Back in the foreground: reconnect now, resuming where it left off.
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _attempt = 0;
    _set(_transcript == null
        ? FeedConnection.connecting
        : FeedConnection.reconnecting);
    start();
  }

  bool get _terminal =>
      _connection == FeedConnection.unauthorized ||
      _connection == FeedConnection.notFound;

  @override
  void dispose() {
    _disposed = true;
    _run++;
    _endStream();
    _wake();
    super.dispose();
  }

  void _set(FeedConnection c) {
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
    final done = _streamDone;
    if (done != null && !done.isCompleted) done.complete();
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
      try {
        await _streamOnce(run);
      } on ViewerUnauthorized {
        if (run != _run) return;
        _run++;
        _set(FeedConnection.unauthorized);
        onUnauthorized?.call();
        return;
      } on ViewerNotFound {
        if (run != _run) return;
        _run++;
        _set(FeedConnection.notFound);
        return;
      } catch (_) {
        // Any other failure is a lost connection: back off and retry.
      }
      if (run != _run) return;
      _set(FeedConnection.reconnecting);
      await _wait(fullJitterBackoff(_attempt++, _random));
    }
  }

  Future<void> _streamOnce(int run) async {
    final done = Completer<void>();
    _streamDone = done;
    DateTime? connectedAt;
    _sub = source(lastEventId: _lastEventId).listen(
      (event) {
        if (run != _run) return;
        connectedAt ??= clock.now();
        _set(FeedConnection.live);
        if (event != null) _apply(event, done);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    try {
      await done.future;
    } finally {
      _sub = null;
      final up = connectedAt;
      if (up != null && clock.now().difference(up) >= stableAfter) {
        _attempt = 0;
      }
    }
  }

  void _apply(FeedEvent event, Completer<void> done) {
    switch (event) {
      case FeedSnapshot():
        _transcript = Transcript(provider: event.provider)
          ..addFrames(event.lines);
        _gen = event.gen;
        _nextLine = event.nextLine;
        _lastEventId = event.id ?? '${event.gen}:${event.nextLine}';
        _changed();
      case FeedAppend():
        final transcript = _transcript;
        final next = _nextLine;
        if (transcript == null ||
            next == null ||
            event.gen != _gen ||
            event.line > next) {
          // Not a continuation of what is shown: start over from a snapshot.
          _resync(done);
          return;
        }
        // Lines already shown (an overlap after a resume) are skipped.
        final skip = next - event.line;
        if (skip < event.lines.length) {
          transcript.addFrames(event.lines.skip(skip));
          _nextLine = event.line + event.lines.length;
        }
        _lastEventId = event.id ?? '$_gen:$_nextLine';
        _changed();
      case FeedReset():
        _clear();
        _changed();
      case FeedStatus():
        _status = event;
        _statusAt = clock.now();
        _changed();
    }
  }

  void _clear() {
    _transcript = null;
    _gen = null;
    _nextLine = null;
    _lastEventId = null;
  }

  /// Drops the resume point and ends the stream; the loop reconnects and
  /// gets a fresh snapshot.
  void _resync(Completer<void> done) {
    _lastEventId = null;
    _gen = null;
    _nextLine = null;
    unawaited(_sub?.cancel());
    _sub = null;
    if (!done.isCompleted) done.complete();
  }
}
