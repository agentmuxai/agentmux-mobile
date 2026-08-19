import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import 'discovery_telemetry.dart';
import 'models/lan_instance.dart';

/// LAN-discovery Layer 2 fallback: a UDP broadcast probe/response, used when
/// mDNS multicast is filtered (corporate/guest WiFi, client isolation).
///
/// Wire protocol (must match the desktop responder exactly — do not change):
///  - Port 47891/UDP.
///  - Probe (broadcast):  {"type":"agentmux_discover","v":1}
///  - Response (unicast): {"type":"agentmux_discover_response","v":1,
///        "instance_id":"...","hostname":"...","version":"...",
///        "port":12345,"auth_key":"..."}
const probePort = 47891;
const _probeMessage = '{"type":"agentmux_discover","v":1}';
const _defaultProbeWindow = Duration(seconds: 2);
const _responseType = 'agentmux_discover_response';

class UdpBroadcastProber {
  /// Broadcasts a discovery probe and yields a [LanInstance] for every valid
  /// response received within [timeout]. The socket is always closed when
  /// the stream ends — whether [timeout] elapses internally or the caller
  /// cancels the stream (e.g. via its own `.timeout()`).
  Stream<LanInstance> probe({Duration timeout = _defaultProbeWindow}) async* {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timer;
    final stopwatch = Stopwatch()..start();
    var probeSent = false;
    var datagramsReceived = 0;
    var validResponses = 0;
    String? errorDetail;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(
        utf8.encode(_probeMessage),
        InternetAddress('255.255.255.255'),
        probePort,
      );
      probeSent = true;

      final controller = StreamController<LanInstance>();

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        datagramsReceived++;
        final instance = parseResponse(datagram);
        if (instance != null) {
          validResponses++;
          controller.add(instance);
        }
      }, onError: (Object e, StackTrace stackTrace) {
        // Socket-level error mid-listen — same graceful-fallback contract
        // as MdnsScanner.scan(), but logged rather than silently swallowed
        // (see that method's catch block for why this matters).
        AppLogger.log(
          'UDP broadcast probe socket error',
          name: 'UdpBroadcastProber',
          error: e,
          stackTrace: stackTrace,
        );
      });

      timer = Timer(timeout, () {
        subscription?.cancel();
        controller.close();
      });

      controller.onCancel = () {
        timer?.cancel();
        subscription?.cancel();
      };

      // NOT "record the outcome after yield* completes" — this point is
      // only reached if `controller.stream` ends on its own accord (its
      // internal `timer` firing). In practice the caller's own `.timeout()`
      // wrapper (discovery_provider.dart) races the same duration and can
      // end this probe via external cancellation instead, which unwinds
      // straight past this line to `finally` (same bug class as
      // MdnsScanner.scan() — reagent P1 on PR #17, fixed there and
      // proactively applied here too). `outcome` is derived in `finally`
      // from `validResponses`/`errorDetail` directly instead.
      yield* controller.stream;
    } catch (e, stackTrace) {
      // Broadcast unavailable (no network, socket bind failure, etc.) —
      // emit nothing, same as MdnsScanner.scan() on failure, but logged
      // rather than silently swallowed so a real regression is diagnosable.
      errorDetail = e.toString();
      AppLogger.log(
        'UDP broadcast probe failed, discovery falls back to remaining layers',
        name: 'UdpBroadcastProber',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket?.close();

      // Unconditional summary, aggregated (not per-datagram — the shared,
      // unauthenticated probe port can legitimately receive unrelated
      // broadcast noise from other devices/apps; logging every single one
      // would flood the ring buffer with signal that isn't about this app).
      // See docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md.
      final outcome = errorDetail != null
          ? 'error'
          : (validResponses > 0 ? 'results' : 'empty');
      final malformed = datagramsReceived - validResponses;
      final detail = outcome == 'error'
          ? 'failed: $errorDetail'
          : '${probeSent ? 'probe sent' : 'probe NOT sent'}, '
              '$datagramsReceived datagram(s) received ($validResponses valid'
              '${malformed > 0 ? ', $malformed malformed/unrelated' : ''}) '
              'in ${stopwatch.elapsedMilliseconds}ms';
      AppLogger.log('UDP broadcast probe complete: $detail',
          name: 'UdpBroadcastProber');
      DiscoveryTelemetry.lastUdpSummary = ScanSummary(
        layer: 'udp_broadcast',
        outcome: outcome,
        detail: detail,
        at: DateTime.now(),
      );
    }
  }

  /// Parses a single UDP datagram into a [LanInstance], or returns null if
  /// it isn't a valid `agentmux_discover_response` (malformed JSON, wrong
  /// type/version, unrelated UDP noise on the port, missing fields).
  ///
  /// `address` is always taken from the datagram's source IP — never from
  /// the JSON body — since the socket-level source address is ground truth
  /// (consistent with how MdnsScanner resolves the A record rather than
  /// trusting a TXT field).
  @visibleForTesting
  static LanInstance? parseResponse(Datagram datagram) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != _responseType) return null;
      if (decoded['v'] != 1) return null;

      final hostname = decoded['hostname'];
      final version = decoded['version'];
      final port = decoded['port'];
      final authKey = decoded['auth_key'];
      final instanceId = decoded['instance_id'];

      if (hostname is! String ||
          version is! String ||
          port is! int ||
          authKey is! String) {
        return null;
      }

      return LanInstance(
        hostname: hostname,
        version: version,
        address: datagram.address.address,
        port: port,
        authKey: authKey,
        instanceId: instanceId is String ? instanceId : null,
      );
    } catch (_) {
      return null;
    }
  }
}
