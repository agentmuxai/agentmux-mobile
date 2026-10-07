import 'dart:async';

import '../logging/app_logger.dart';
import 'cloud_instances.dart';

/// What the cloud host list currently says, for the note under the host list
/// (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 4.5).
enum CloudListStatus {
  /// Not asked yet.
  pending,

  /// Not signed in, or a build with no cloud settings: cloud hosts are not
  /// shown, and the screen says so.
  signedOut,

  /// The list was read.
  ok,

  /// Signed in, but reading the list failed; the reason is in the debug log.
  unavailable,

  /// The relay predates the list (404). Not an error worth a note.
  unsupported,
}

/// What a [CloudInstanceSource] reports to its owner.
sealed class CloudUpdate {
  const CloudUpdate();
}

class CloudSignedOut extends CloudUpdate {
  const CloudSignedOut();
}

class CloudFetched extends CloudUpdate {
  const CloudFetched(this.instances);
  final List<CloudInstance> instances;
}

class CloudUnavailable extends CloudUpdate {
  const CloudUnavailable(this.error);
  final Object error;
}

class CloudUnsupported extends CloudUpdate {
  const CloudUnsupported();
}

/// Keeps the account's cloud install list current while it runs: one fetch
/// on start, then every [interval]; [refresh] fetches at once. Signed out,
/// it fetches nothing and reports [CloudSignedOut] (checked every cycle, so
/// signing in or out is noticed). An older relay (404) is asked again only
/// every [unsupportedRetry]. One-shot like a channel session: the owner stops
/// it in the background and starts a new one on return.
///
/// [isSignedIn] and [fetch] are the transport, and timing reads `Timer`, so
/// tests drive it with `fake_async` and no network.
class CloudInstanceSource {
  CloudInstanceSource({
    required this.isSignedIn,
    required this.fetch,
    required this.onUpdate,
  });

  final Future<bool> Function() isSignedIn;
  final Future<List<CloudInstance>> Function() fetch;
  final void Function(CloudUpdate) onUpdate;

  static const interval = Duration(seconds: 30);
  static const unsupportedRetry = Duration(minutes: 10);

  bool _running = false;
  bool _stopped = false;
  Timer? _sleepTimer;
  Completer<void>? _sleep;
  var _waiters = <Completer<void>>[];
  String? _lastLogged;

  void start() {
    if (_running || _stopped) return;
    _running = true;
    unawaited(_run());
  }

  /// Ends the source for good; nothing is reported after this returns.
  void stop() {
    _stopped = true;
    _wake();
    _release(_waiters);
    _waiters = [];
  }

  /// Fetches now. Completes when a fetch that started after this call has
  /// finished (or at once when the source is not running).
  Future<void> refresh() {
    if (!_running || _stopped) return Future.value();
    final c = Completer<void>();
    _waiters.add(c);
    _wake();
    return c.future;
  }

  Future<void> _run() async {
    while (!_stopped) {
      final waiters = _waiters;
      _waiters = [];
      final delay = await _cycle();
      _release(waiters);
      if (_stopped) return;
      // A refresh that arrived mid-fetch wants a fetch of its own.
      if (_waiters.isNotEmpty) continue;
      await _wait(delay);
    }
  }

  Future<Duration> _cycle() async {
    bool signedIn;
    try {
      signedIn = await isSignedIn();
    } catch (_) {
      // No token store (tests, an unsupported platform) is "not signed in".
      signedIn = false;
    }
    if (_stopped) return interval;
    if (!signedIn) {
      _report(const CloudSignedOut());
      return interval;
    }
    try {
      final instances = await fetch();
      _lastLogged = null;
      _report(CloudFetched(instances));
      return interval;
    } on CloudInstancesUnsupported {
      _log('Cloud host list not served by this relay (404); '
          'retrying in ${unsupportedRetry.inMinutes} min');
      _report(const CloudUnsupported());
      return unsupportedRetry;
    } catch (e, stackTrace) {
      // Logged once per distinct failure, not every 30 s. The request's
      // auth header is never part of the error text.
      _log('Cloud host list unavailable', error: e, stackTrace: stackTrace);
      _report(CloudUnavailable(e));
      return interval;
    }
  }

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    final text = '$message${error == null ? '' : ': ${error.runtimeType}'}';
    if (text == _lastLogged) return;
    _lastLogged = text;
    AppLogger.log(
      message,
      name: 'CloudInstanceSource',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _report(CloudUpdate u) {
    if (!_stopped) onUpdate(u);
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

  static void _release(List<Completer<void>> waiters) {
    for (final w in waiters) {
      if (!w.isCompleted) w.complete();
    }
  }
}
