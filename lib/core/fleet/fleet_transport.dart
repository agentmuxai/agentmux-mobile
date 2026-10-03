import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../discovery/local_api_client.dart';
import '../discovery/models/lan_instance.dart';
import 'fleet_snapshot.dart';
import 'sse.dart';

/// The desktop does not serve this route (an older srv): the session should
/// fall back to the next mode rather than retry.
class FleetFeedUnsupported implements Exception {
  const FleetFeedUnsupported(this.route);
  final String route;

  @override
  String toString() => 'FleetFeedUnsupported($route)';
}

/// Outcome of one conditional `GET /agentmux/fleet`.
sealed class FleetPoll {
  const FleetPoll();
}

class FleetFetched extends FleetPoll {
  const FleetFetched(this.snapshot);
  final FleetSnapshot snapshot;
}

class FleetNotModified extends FleetPoll {
  const FleetNotModified();
}

/// What the pre-fleet-feed routes report (`/agentmux/discovery`, falling back
/// to `/agentmux/reactive/agent-names` for a `lan_key`).
typedef LegacyFleetInfo = ({
  String hostname,
  String version,
  String? channel,
  List<LanAgent> agents,
});

/// How a session talks to one channel. An interface so the session's
/// timing and fallback logic can be tested against a scripted fake.
abstract class FleetTransport {
  /// Opens the push stream. Emits `null` once the server accepted the stream
  /// and again for every heartbeat or other non-event bytes (proof of life),
  /// and a snapshot for every `fleet` event. Errors with
  /// [FleetFeedUnsupported] for an older srv, a [TimeoutException] after
  /// [idleTimeout] of silence, or the underlying network error.
  Stream<FleetSnapshot?> events({String? lastEventId});

  /// One conditional fetch; [etag] is the previous `epoch:rev`.
  Future<FleetPoll> poll({String? etag});

  /// The legacy routes, for an srv that predates the fleet feed, or for a
  /// full-key (QR/manual) connection, where `/agentmux/discovery` also
  /// reports the other channels on that machine.
  Future<LegacyFleetInfo> legacy();
}

/// [FleetTransport] over HTTP to `http://address:port` with `X-AuthKey`.
class HttpFleetTransport implements FleetTransport {
  HttpFleetTransport(this.address, this.port, this.authKey, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'http://$address:$port',
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'X-AuthKey': authKey},
            ));

  final String address;
  final int port;
  final String authKey;
  final Dio _dio;

  /// One client for the session's lifetime: a new one per poll would leave a
  /// connection pool behind every few seconds.
  late final LocalApiClient _legacy =
      LocalApiClient.fromParts(address, port, authKey);

  /// Two missed 15 s heartbeats (spec section 6).
  static const idleTimeout = Duration(seconds: 30);

  static bool _unsupported(int? status) =>
      status == 404 || status == 405 || status == 501;

  @override
  Stream<FleetSnapshot?> events({String? lastEventId}) {
    final cancel = CancelToken();
    StreamSubscription<List<int>>? bytesSub;
    late final StreamController<FleetSnapshot?> out;
    out = StreamController<FleetSnapshot?>(
      onListen: () async {
        try {
          final res = await _dio.get<ResponseBody>(
            '/agentmux/fleet/events',
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.stream,
              // The stream is long-lived; idleness is policed below instead.
              receiveTimeout: idleTimeout + const Duration(seconds: 15),
              headers: {
                'Accept': 'text/event-stream',
                if (lastEventId != null) 'Last-Event-ID': lastEventId,
              },
            ),
          );
          final body = res.data;
          if (body == null) throw const FleetFeedUnsupported('fleet/events');
          out.add(null);
          final parser = SseParser();
          final decoder = const Utf8Decoder(allowMalformed: true)
              .startChunkedConversion(_SinkFn((text) {
            out.add(null);
            for (final e in parser.add(text)) {
              if (e.event != 'fleet') continue;
              final snap = FleetSnapshot.tryParse(_tryJson(e.data));
              if (snap != null) out.add(snap);
            }
          }));
          bytesSub = body.stream.timeout(idleTimeout).listen(
                decoder.add,
                onError: (Object e, StackTrace st) {
                  out.addError(e, st);
                  out.close();
                },
                onDone: out.close,
                cancelOnError: true,
              );
        } on DioException catch (e, st) {
          if (_unsupported(e.response?.statusCode)) {
            out.addError(const FleetFeedUnsupported('fleet/events'), st);
          } else {
            out.addError(e, st);
          }
          await out.close();
        } catch (e, st) {
          out.addError(e, st);
          await out.close();
        }
      },
      onCancel: () async {
        cancel.cancel();
        await bytesSub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<FleetPoll> poll({String? etag}) async {
    try {
      final res = await _dio.get<Object>(
        '/agentmux/fleet',
        options: Options(
          headers: {if (etag != null) 'If-None-Match': '"$etag"'},
          validateStatus: (s) => s != null && (s < 300 || s == 304),
        ),
      );
      if (res.statusCode == 304) return const FleetNotModified();
      final snap = FleetSnapshot.tryParse(res.data);
      if (snap == null) throw const FormatException('not a fleet body');
      return FleetFetched(snap);
    } on DioException catch (e) {
      if (_unsupported(e.response?.statusCode)) {
        throw const FleetFeedUnsupported('fleet');
      }
      rethrow;
    }
  }

  @override
  Future<LegacyFleetInfo> legacy() => _legacy.fetchDiscoveryInfo();

  static Object? _tryJson(String data) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }
}

class _SinkFn implements Sink<String> {
  _SinkFn(this._onData);
  final void Function(String) _onData;

  @override
  void add(String data) => _onData(data);

  @override
  void close() {}
}
