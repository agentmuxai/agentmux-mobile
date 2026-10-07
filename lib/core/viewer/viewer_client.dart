import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../discovery/models/lan_instance.dart';
import '../discovery/peer_fields.dart';
import '../fleet/sse.dart';
import 'feed_events.dart';
import 'pinned_tls.dart';

/// The desktop refused the viewer token (`401`): it was revoked on the
/// computer, or the computer forgot it.
class ViewerUnauthorized implements Exception {
  const ViewerUnauthorized();

  @override
  String toString() => 'ViewerUnauthorized';
}

/// `404`: the agent is unknown or hidden from paired devices.
class ViewerNotFound implements Exception {
  const ViewerNotFound();

  @override
  String toString() => 'ViewerNotFound';
}

/// Why pairing failed, each with what the user can do about it.
enum PairingFailure {
  /// `401`: the code expired, was used, or was mistyped.
  codeRejected,

  /// `429`: too many wrong codes.
  rateLimited,

  /// The computer's certificate is not the one in the QR code.
  certificateMismatch,

  /// No answer, or one that is not a pairing response.
  unreachable,
}

class PairingException implements Exception {
  const PairingException(this.failure);
  final PairingFailure failure;

  String get message => switch (failure) {
        PairingFailure.codeRejected =>
          'That code has expired or was already used. Show a new code on the '
              'computer and scan it again.',
        PairingFailure.rateLimited =>
          'Too many attempts. Wait a minute, then scan a new code.',
        PairingFailure.certificateMismatch =>
          'The computer that answered is not the one in the QR code. Pairing '
              'was stopped.',
        PairingFailure.unreachable =>
          'Could not reach the computer. Check that this device is on the same '
              'network, then try again.',
      };

  @override
  String toString() => 'PairingException($failure)';
}

/// What `POST /agentmux/viewer/pair` returns.
class PairResult {
  const PairResult({
    required this.token,
    required this.deviceId,
    this.hostname,
    this.channel,
    this.version,
    this.installId,
  });
  final String token;
  final String deviceId;
  final String? hostname;
  final String? channel;
  final String? version;
  final String? installId;
}

/// `GET /agentmux/viewer/hello`.
class ViewerHello {
  const ViewerHello({
    required this.hostname,
    required this.deviceId,
    this.channel,
    this.version,
    this.installId,
  });
  final String hostname;
  final String deviceId;
  final String? channel;
  final String? version;
  final String? installId;
}

/// One entry of `GET /agentmux/viewer/agents`.
class ViewerAgent {
  const ViewerAgent({required this.name, this.kind, this.state, this.sinceMs});
  final String name;
  final AgentKind? kind;
  final String? state;
  final int? sinceMs;
}

class ViewerAgents {
  const ViewerAgents({required this.agents, this.nowMs});
  final List<ViewerAgent> agents;
  final int? nowMs;
}

/// A token is sent in a header, so only header-safe characters are kept.
final _tokenPattern = RegExp(r'^[A-Za-z0-9._~+/=-]{1,512}$');

/// Talks to one computer's viewer listener
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 13.2 and 13.3), over
/// TLS pinned to [fingerprint], with the viewer [token] once paired.
class ViewerClient {
  ViewerClient({
    required this.host,
    required this.port,
    required this.fingerprint,
    this.token,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(BaseOptions(
          baseUrl: 'https://${host.contains(':') ? '[$host]' : host}:$port',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ))
          ..httpClientAdapter = adapter ?? pinnedAdapter(fingerprint);

  final String host;
  final int port;
  final String fingerprint;
  final String? token;
  final Dio _dio;

  /// Two missed 15 s heartbeats.
  static const idleTimeout = Duration(seconds: 30);

  void close() => _dio.close(force: true);

  /// `POST /agentmux/viewer/pair`. Throws [PairingException].
  Future<PairResult> pair({
    required String code,
    required String deviceName,
  }) async {
    final Response<Object?> res;
    try {
      res = await _dio.post<Object?>(
        '/agentmux/viewer/pair',
        data: {
          'code': code,
          'device_name': deviceName,
        },
      );
    } on DioException catch (e) {
      if (isPinRejection(e)) {
        throw const PairingException(PairingFailure.certificateMismatch);
      }
      throw PairingException(switch (e.response?.statusCode) {
        401 => PairingFailure.codeRejected,
        429 => PairingFailure.rateLimited,
        _ => PairingFailure.unreachable,
      });
    }
    final result = parsePairResult(res.data);
    if (result == null) {
      throw const PairingException(PairingFailure.unreachable);
    }
    return result;
  }

  /// `GET /agentmux/viewer/hello`. Throws [ViewerUnauthorized] on a 401.
  Future<ViewerHello> hello() async {
    final data = await _get('/agentmux/viewer/hello');
    final hello = parseHello(data);
    if (hello == null) throw const FormatException('not a hello body');
    return hello;
  }

  /// `GET /agentmux/viewer/agents`. Throws [ViewerUnauthorized] on a 401.
  Future<ViewerAgents> agents() async {
    final data = await _get('/agentmux/viewer/agents');
    final agents = parseAgents(data);
    if (agents == null) throw const FormatException('not an agents body');
    return agents;
  }

  Future<Object?> _get(String path) async {
    try {
      return (await _dio.get<Object?>(path)).data;
    } on DioException catch (e) {
      throw _mapped(e);
    }
  }

  static Object _mapped(DioException e) => switch (e.response?.statusCode) {
        401 => const ViewerUnauthorized(),
        404 => const ViewerNotFound(),
        _ => e,
      };

  /// Opens one agent's feed. Emits `null` once the server accepted the
  /// stream and again for every chunk received (heartbeats included: proof
  /// of life), and each [FeedEvent]. Errors with [ViewerUnauthorized],
  /// [ViewerNotFound], a [TimeoutException] after [idleTimeout] of silence,
  /// or the network error.
  Stream<FeedEvent?> feed(String agent, {String? lastEventId}) {
    final cancel = CancelToken();
    StreamSubscription<List<int>>? bytesSub;
    late final StreamController<FeedEvent?> out;
    out = StreamController<FeedEvent?>(
      onListen: () async {
        try {
          final res = await _dio.get<ResponseBody>(
            '/agentmux/viewer/agents/${Uri.encodeComponent(agent)}/feed',
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.stream,
              receiveTimeout: idleTimeout + const Duration(seconds: 15),
              headers: {
                'Accept': 'text/event-stream',
                if (lastEventId != null) 'Last-Event-ID': lastEventId,
              },
            ),
          );
          final body = res.data;
          if (body == null) throw const FormatException('no feed body');
          if (out.isClosed) return;
          out.add(null);
          void fail(Object e, StackTrace st) {
            if (out.isClosed) return;
            cancel.cancel();
            unawaited(bytesSub?.cancel());
            out.addError(e, st);
            unawaited(out.close());
          }

          final parser = SseParser();
          final decoder = const Utf8Decoder(allowMalformed: true)
              .startChunkedConversion(_SinkFn((text) {
            if (out.isClosed) return;
            final List<SseEvent> events;
            try {
              events = parser.add(text);
            } on FormatException catch (e, st) {
              fail(e, st);
              return;
            }
            out.add(null);
            for (final e in events) {
              final event = parseFeedEvent(e);
              if (event != null) out.add(event);
            }
          }));
          bytesSub = body.stream.timeout(idleTimeout).listen(
                decoder.add,
                onError: fail,
                onDone: () {
                  if (!out.isClosed) unawaited(out.close());
                },
                cancelOnError: true,
              );
        } on DioException catch (e, st) {
          if (!out.isClosed) {
            out.addError(_mapped(e), st);
            await out.close();
          }
        } catch (e, st) {
          if (!out.isClosed) {
            out.addError(e, st);
            await out.close();
          }
        }
      },
      onCancel: () async {
        cancel.cancel();
        await bytesSub?.cancel();
      },
    );
    return out.stream;
  }

  static PairResult? parsePairResult(Object? json) {
    if (json is! Map) return null;
    final token = json['token'];
    final deviceId = _short(json['device_id']);
    if (token is! String || !_tokenPattern.hasMatch(token)) return null;
    if (deviceId == null || deviceId.isEmpty) return null;
    return PairResult(
      token: token,
      deviceId: deviceId,
      hostname: _short(json['hostname']),
      channel: _short(json['channel']),
      version: _short(json['version']),
      installId: parseInstallId(json['install_id']),
    );
  }

  static ViewerHello? parseHello(Object? json) {
    if (json is! Map) return null;
    final hostname = _short(json['hostname']);
    final deviceId = _short(json['device_id']);
    if (hostname == null || deviceId == null) return null;
    return ViewerHello(
      hostname: hostname,
      deviceId: deviceId,
      channel: _short(json['channel']),
      version: _short(json['version']),
      installId: parseInstallId(json['install_id']),
    );
  }

  static ViewerAgents? parseAgents(Object? json) {
    if (json is! Map) return null;
    final list = json['agents'];
    if (list is! List) return null;
    final now = json['now_ms'];
    return ViewerAgents(
      nowMs: now is int ? now : null,
      agents: [
        for (final a in list.take(500))
          if (a is Map &&
              a['name'] is String &&
              (a['name'] as String).isNotEmpty &&
              (a['name'] as String).length <= 128)
            ViewerAgent(
              name: a['name'] as String,
              kind: parseAgentKind(a['kind']),
              state: _short(a['state']),
              sinceMs: a['since_ms'] is int ? a['since_ms'] as int : null,
            ),
      ],
    );
  }

  static String? _short(Object? v) =>
      v is String && v.length <= 128 && !hasControlChar(v) ? v : null;
}

class _SinkFn implements Sink<String> {
  _SinkFn(this._onData);
  final void Function(String) _onData;

  @override
  void add(String data) => _onData(data);

  @override
  void close() {}
}
