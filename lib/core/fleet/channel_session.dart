import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

import '../discovery/models/lan_instance.dart';
import 'fleet_snapshot.dart';
import 'fleet_transport.dart';

/// Why a channel could not be read. Shown to the user as such, never as an
/// empty agent list (spec P12).
enum ChannelError { unreachable, unauthorized }

/// How a session is currently reading its channel.
enum SessionMode {
  /// `/agentmux/fleet/events` (push).
  stream,

  /// Conditional `GET /agentmux/fleet`.
  poll,

  /// `/agentmux/discovery`, or agent names for a `lan_key` (older srv, or a
  /// full-key connection, which also learns the machine's other channels).
  legacy,
}

/// What a session reports to its owner.
sealed class SessionUpdate {
  const SessionUpdate();
}

/// The channel answered. [agents] is null when the answer carried no new
/// state (a heartbeat, a 304, or an accepted stream before its first event).
class SessionContact extends SessionUpdate {
  const SessionContact({
    this.agents,
    this.epoch,
    this.rev,
    this.hostname,
    this.channel,
    this.version,
    this.os,
    this.installId,
    this.channelsRunning,
  });

  final List<LanAgent>? agents;
  final String? epoch;
  final int? rev;
  final String? hostname;
  final String? channel;
  final String? version;
  final String? os;
  final String? installId;
  final int? channelsRunning;
}

class SessionFailure extends SessionUpdate {
  const SessionFailure(this.error);
  final ChannelError error;
}

/// Full-jitter exponential backoff (spec P5): random(0, min(cap, base*2^n)).
Duration fullJitterBackoff(
  int attempt,
  Random random, {
  Duration base = const Duration(seconds: 1),
  Duration cap = const Duration(seconds: 60),
}) {
  final exp = base.inMilliseconds * pow(2, min(attempt, 16));
  final ceiling = min(cap.inMilliseconds, exp.toInt());
  return Duration(milliseconds: random.nextInt(max(ceiling, 1)));
}

/// Keeps one channel's state current, for as long as it runs.
///
/// Tries the push stream first and falls back, route by route, for an older
/// srv (spec 4.5). A dead stream is detected by silence (the transport's idle
/// timeout), not by waiting for TCP to notice. Every failure backs off with
/// full jitter; a 401 retries slowly. Timing reads `clock` and `Timer`, so
/// tests drive it with `fake_async`.
class ChannelSession {
  ChannelSession({
    required this.transport,
    required this.onUpdate,
    this.startMode = SessionMode.stream,
    Random? random,
  }) : _random = random ?? Random();

  final FleetTransport transport;
  final void Function(SessionUpdate) onUpdate;
  final SessionMode startMode;
  final Random _random;

  static const activePollInterval = Duration(seconds: 3);
  static const quietPollInterval = Duration(seconds: 10);
  static const recentChangeWindow = Duration(minutes: 1);
  static const unauthorizedRetry = Duration(seconds: 60);

  /// A stream that stayed up this long resets the backoff.
  static const stableAfter = Duration(seconds: 30);

  SessionMode _mode = SessionMode.stream;
  SessionMode get mode => _mode;

  bool _running = false;
  bool _stopped = false;
  int _attempt = 0;
  String? _lastEventId;
  String? _etag;
  DateTime? _lastChangeAt;

  Timer? _sleepTimer;
  Completer<void>? _sleep;
  StreamSubscription<FleetSnapshot?>? _sub;
  Completer<void>? _streamDone;

  void start() {
    if (_running || _stopped) return;
    _running = true;
    _mode = startMode;
    unawaited(_run());
  }

  /// Ends the session for good; no update is reported after this returns.
  void stop() {
    _stopped = true;
    unawaited(_sub?.cancel());
    _sub = null;
    final done = _streamDone;
    if (done != null && !done.isCompleted) done.complete();
    _wake();
  }

  /// Skips any pending wait (pull-to-refresh, coming back to the foreground).
  void resync() => _wake();

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

  void _report(SessionUpdate u) {
    if (!_stopped) onUpdate(u);
  }

  Duration _pollInterval() {
    final changed = _lastChangeAt;
    final base = changed != null &&
            clock.now().difference(changed) < recentChangeWindow
        ? activePollInterval
        : quietPollInterval;
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    return Duration(milliseconds: (base.inMilliseconds * jitter).round());
  }

  Future<void> _run() async {
    while (!_stopped) {
      try {
        switch (_mode) {
          case SessionMode.stream:
            await _streamOnce();
            if (_stopped) return;
            await _wait(fullJitterBackoff(_attempt++, _random));
          case SessionMode.poll:
            await _pollOnce();
            _attempt = 0;
            await _wait(_pollInterval());
          case SessionMode.legacy:
            await _legacyOnce();
            _attempt = 0;
            await _wait(_pollInterval());
        }
      } on FleetFeedUnsupported {
        _mode = _mode == SessionMode.stream
            ? SessionMode.poll
            : SessionMode.legacy;
      } on DioException catch (e) {
        if (_stopped) return;
        if (e.response?.statusCode == 401) {
          _report(const SessionFailure(ChannelError.unauthorized));
          await _wait(unauthorizedRetry);
        } else {
          _report(const SessionFailure(ChannelError.unreachable));
          await _wait(fullJitterBackoff(_attempt++, _random));
        }
      } catch (_) {
        if (_stopped) return;
        _report(const SessionFailure(ChannelError.unreachable));
        await _wait(fullJitterBackoff(_attempt++, _random));
      }
    }
  }

  Future<void> _streamOnce() async {
    final done = Completer<void>();
    _streamDone = done;
    DateTime? connectedAt;
    _sub = transport.events(lastEventId: _lastEventId).listen(
      (item) {
        connectedAt ??= clock.now();
        if (item == null) {
          _report(const SessionContact());
          return;
        }
        _lastEventId = item.eventId;
        _lastChangeAt = clock.now();
        _report(_contactFrom(item));
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
    // A stream the server closed cleanly is still a lost connection, but
    // only an outage if it never connected.
    if (connectedAt == null && !_stopped) {
      _report(const SessionFailure(ChannelError.unreachable));
    }
  }

  Future<void> _pollOnce() async {
    final r = await transport.poll(etag: _etag);
    switch (r) {
      case FleetNotModified():
        _report(const SessionContact());
      case FleetFetched(:final snapshot):
        if (_etag != snapshot.eventId) _lastChangeAt = clock.now();
        _etag = snapshot.eventId;
        _report(_contactFrom(snapshot));
    }
  }

  List<LanAgent>? _lastLegacy;

  Future<void> _legacyOnce() async {
    final info = await transport.legacy();
    final changed = _lastLegacy == null || !_sameAgents(_lastLegacy!, info.agents);
    if (changed) _lastChangeAt = clock.now();
    _lastLegacy = info.agents;
    _report(SessionContact(
      agents: info.agents,
      hostname: info.hostname.isEmpty ? null : info.hostname,
      channel: info.channel,
      version: info.version == 'unknown' ? null : info.version,
    ));
  }

  static bool _sameAgents(List<LanAgent> a, List<LanAgent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name ||
          a[i].channel != b[i].channel ||
          a[i].kind != b[i].kind) {
        return false;
      }
    }
    return true;
  }

  static SessionContact _contactFrom(FleetSnapshot s) => SessionContact(
        agents: [
          for (final n in s.agents)
            LanAgent(name: n, kind: s.agentKinds[n.toLowerCase()]),
        ],
        epoch: s.epoch,
        rev: s.rev,
        hostname: s.hostname.isEmpty ? null : s.hostname,
        channel: s.channel,
        version: s.version.isEmpty ? null : s.version,
        os: s.os,
        installId: s.installId,
        channelsRunning: s.channelsRunning,
      );
}
