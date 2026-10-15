import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import '../../core/viewer/device_key_store.dart';
import '../../core/viewer/paired_host.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/viewer_client.dart';

/// The longest message the computer takes, in UTF-8 bytes.
const maxMessageBytes = 10000;

/// Where a message a person sent from this phone is.
enum SentState {
  /// On its way to the computer.
  sending,

  /// The computer took it; the feed has not shown it yet.
  taken,

  /// It did not go. The text is kept for [SendController.retry].
  failed,
}

/// Why a send failed, for the words under the message.
enum SendFailure {
  /// A refusal from the computer ([SentMessage.refusal]).
  refused,

  /// No answer: the computer is off, asleep or out of reach.
  unreachable,

  /// The computer no longer knows this device.
  unpaired,

  /// This device's key is gone or failed to sign: pair again.
  key,
}

/// One message sent from this phone, from Enter until the feed shows it.
class SentMessage {
  SentMessage(this.id, this.text);

  /// Made when the person pressed Enter and reused for every retry, so a
  /// message whose answer was lost is never delivered twice.
  final String id;
  final String text;
  SentState state = SentState.sending;
  SendFailure? failure;
  SendRefused? refusal;
}

/// Sends messages to one agent on a paired computer
/// (`SPEC_SEND_FROM_THE_PHONE_2026_10_13.md` 5.2.1 and 5.5): asks whether this
/// device may ([grant]), signs and posts each message, keeps what is in
/// flight and what failed, and drops a message once the feed shows it.
class SendController extends ChangeNotifier {
  SendController({
    required this.clientFor,
    required this.pairing,
    required this.agent,
    required this.keys,
    this.onUnauthorized,
    this.takenFor = const Duration(seconds: 30),
    this.inFlightWait = const Duration(seconds: 1),
    Random? random,
  }) : _random = random ?? Random.secure();

  final ViewerClientFactory clientFor;
  final PairingMatch pairing;
  final String agent;
  final DeviceKeyStore keys;

  /// The computer refused this device's token.
  final VoidCallback? onUnauthorized;
  final Random _random;

  /// How long a message the computer took stays as "Sending…" if the feed
  /// never shows it (a feed that was paused, a transcript that moved on).
  final Duration takenFor;

  /// An `in_flight` answer (this message is being sent right now) is asked
  /// again after this, up to [inFlightRetries] times.
  final Duration inFlightWait;
  static const inFlightRetries = 3;

  SendGrant? _grant;

  /// Whether the computer takes messages from this device; null until asked.
  SendGrant? get grant => _grant;

  final _messages = <SentMessage>[];

  /// What was sent and is not in the feed yet, oldest first.
  List<SentMessage> get messages => List.unmodifiable(_messages);

  final _timers = <String, Timer>{};
  bool _disposed = false;

  /// Reads `hello.send`. A computer that does not answer leaves it as it was.
  Future<void> checkGrant() async {
    final client = _client();
    try {
      final hello = await client.hello();
      _setGrant(hello.send);
    } on ViewerUnauthorized {
      onUnauthorized?.call();
    } on Object {
      // Unreachable: the feed says so; the composer waits for an answer.
    } finally {
      client.close();
    }
  }

  void _setGrant(SendGrant grant) {
    if (_disposed || _grant == grant) return;
    _grant = grant;
    notifyListeners();
  }

  ViewerClient _client() {
    final paired = pairing.paired;
    return clientFor(
      host: pairing.host,
      port: pairing.port,
      fingerprint: paired.fingerprint,
      token: paired.token,
    );
  }

  /// Sends [text] (trailing white space trimmed). Returns false for a message
  /// that is empty or over [maxMessageBytes]: nothing was sent.
  bool send(String text) {
    final message = text.trimRight();
    if (_disposed || message.trim().isEmpty || utf8.encode(message).length > maxMessageBytes) {
      return false;
    }
    final sent = SentMessage(newMessageId(_random), message);
    _log('send', sent);
    _messages.add(sent);
    notifyListeners();
    unawaited(_attempt(sent));
    return true;
  }

  /// Sends a failed message again, with the id it already has.
  void retry(String id) {
    final sent = _find(id);
    if (_disposed || sent == null || sent.state != SentState.failed) return;
    _log('retry', sent);
    sent
      ..state = SentState.sending
      ..failure = null
      ..refusal = null;
    notifyListeners();
    unawaited(_attempt(sent));
  }

  /// Forgets a failed message.
  void discard(String id) {
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == id && m.state == SentState.failed);
    if (_messages.length != before) notifyListeners();
  }

  /// The feed now shows these message ids: they are no longer "Sending…".
  void shown(bool Function(String id) inFeed) {
    final before = _messages.length;
    _messages.removeWhere((m) {
      if (m.state == SentState.failed || !inFeed(m.id)) return false;
      _timers.remove(m.id)?.cancel();
      return true;
    });
    if (_messages.length != before && !_disposed) notifyListeners();
  }

  SentMessage? _find(String id) {
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _attempt(SentMessage sent, {int inFlight = 0}) async {
    final client = _client();
    try {
      final result = await client.sendInput(
        agent,
        message: sent.text,
        messageId: sent.id,
        sign: (text) => keys.sign(deviceKeyAlias(pairing.paired.id), text),
      );
      if (_disposed || !_messages.contains(sent)) return;
      switch (result) {
        case SendAccepted():
          _log('accepted', sent);
          sent.state = SentState.taken;
          _timers[sent.id] = Timer(takenFor, () {
            if (_messages.remove(sent) && !_disposed) notifyListeners();
          });
          notifyListeners();
        case SendRefused(kind: SendRefusal.inFlight) when inFlight < inFlightRetries:
          // The same message is being sent right now: ask again shortly.
          await Future<void>.delayed(inFlightWait);
          if (_disposed || !_messages.contains(sent)) return;
          await _attempt(sent, inFlight: inFlight + 1);
          return;
        case SendRefused():
          _refused(sent, result);
      }
    } on ViewerUnauthorized {
      _fail(sent, SendFailure.unpaired);
      onUnauthorized?.call();
    } on DeviceKeyException {
      _fail(sent, SendFailure.key);
    } on Object {
      _fail(sent, SendFailure.unreachable);
    } finally {
      client.close();
    }
  }

  void _refused(SentMessage sent, SendRefused refusal) {
    // What a refusal says about this device's standing, the composer follows.
    switch (refusal.kind) {
      case SendRefusal.sendOff:
        _setGrant(SendGrant.off);
      case SendRefusal.pairAgain:
        _setGrant(SendGrant.pairAgain);
      default:
    }
    sent.refusal = refusal;
    _log('refused (${refusal.kind.name})', sent);
    _fail(sent, SendFailure.refused);
  }

  void _fail(SentMessage sent, SendFailure failure) {
    if (_disposed || !_messages.contains(sent)) return;
    if (failure != SendFailure.refused) _log('failed (${failure.name})', sent);
    sent
      ..state = SentState.failed
      ..failure = failure;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// The in-app debug log line for a step of a send: the message id and the text's
/// length in characters and UTF-8 bytes, never the text itself, so a report like
/// "the computer got a different text for this id" can be checked against what
/// the phone held at each step.
@visibleForTesting
String sendLogLine(String step, SentMessage sent) =>
    '$step ${sent.id}: ${sent.text.length} chars, ${utf8.encode(sent.text).length} bytes';

void _log(String step, SentMessage sent) => AppLogger.log(sendLogLine(step, sent), name: 'Send');

/// A random (version 4) UUID.
String newMessageId(Random random) {
  final b = Uint8List.fromList([for (var i = 0; i < 16; i++) random.nextInt(256)]);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) =>
      [for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0')].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// What to tell the person under a message that did not go.
String sendFailureText(SentMessage sent) => switch (sent.failure) {
      SendFailure.unreachable => "Didn't send: can't reach the computer.",
      SendFailure.unpaired => "Didn't send: this device was unpaired on the computer.",
      SendFailure.key => "Didn't send: this device's key is gone. Pair again to send.",
      SendFailure.refused => switch (sent.refusal?.kind) {
          SendRefusal.sendOff => "Didn't send: sending is off for this device.",
          SendRefusal.pairAgain => "Didn't send: pair this device again to send.",
          SendRefusal.badSignature => "Didn't send: the computer didn't accept this device's key. Pair again.",
          SendRefusal.staleTimestamp => "Didn't send: this phone's clock is off by more than a minute.",
          SendRefusal.noSuchAgent => "Didn't send: this agent is not available on the computer.",
          SendRefusal.notRunning => "Didn't send: nothing is running this agent. Open it on the computer.",
          SendRefusal.starting => "Didn't send: the agent is still starting.",
          SendRefusal.needsLogin => "Didn't send: the agent needs to sign in on the computer.",
          SendRefusal.inFlight => "Didn't send: the computer is still taking this message.",
          SendRefusal.notSupported => "Didn't send: this agent runs in a terminal pane and can't take messages here.",
          SendRefusal.failed => "Didn't send: the computer couldn't deliver it.",
          SendRefusal.tooLong => "Didn't send: the message is too long.",
          SendRefusal.rateLimited => "Didn't send: too many messages. Wait a minute.",
          SendRefusal.badRequest => "Didn't send: the computer didn't understand the message.",
          SendRefusal.other || null => "Didn't send.",
        },
      null => "Didn't send.",
    };
