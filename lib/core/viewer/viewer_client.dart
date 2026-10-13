import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../discovery/models/lan_instance.dart';
import '../discovery/peer_fields.dart';
import '../fleet/sse.dart';
import 'feed_events.dart';
import 'pinned_tls.dart';
import 'terminal_events.dart';

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

/// `403`: the computer doesn't share this (its terminals, while the user
/// hasn't turned sharing on).
class ViewerForbidden implements Exception {
  const ViewerForbidden();

  @override
  String toString() => 'ViewerForbidden';
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

/// What a device can do with a pane.
enum PaneKind {
  /// An agent: its feed opens by [ViewerPane.agent].
  agent,
  terminal,

  /// Any other pane (editor, browser, files, a widget, ...): opened on the
  /// computer.
  other,
}

/// One entry of `GET /agentmux/viewer/panes`.
class ViewerPane {
  const ViewerPane({
    required this.blockId,
    required this.view,
    required this.kind,
    required this.label,
    required this.windowId,
    required this.window,
    required this.tabId,
    required this.tab,
    this.tabActive = false,
    this.agent,
    this.running,
    this.parentBlockId,
  });
  final String blockId;

  /// The desktop's view id (`agent`, `term`, `editor`, `ext:<id>`, ...).
  final String view;
  final PaneKind kind;
  final String label;
  final String windowId;
  final String window;
  final String tabId;
  final String tab;
  final bool tabActive;

  /// For an agent: the name its feed opens by, while it is registered.
  final String? agent;

  /// For a terminal: whether its shell runs; null when not known.
  final bool? running;

  /// For an agent's shell: the agent pane it belongs to.
  final String? parentBlockId;
}

/// What `GET /agentmux/viewer/panes` returns.
class ViewerPanes {
  const ViewerPanes({required this.panes, this.terminalsShared = false});
  final List<ViewerPane> panes;

  /// Whether the computer lets this device watch its terminals.
  final bool terminalsShared;
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

  /// `GET /agentmux/viewer/panes`: every pane on the computer, in the
  /// desktop's order. Throws [ViewerUnauthorized] on a 401, and
  /// [ViewerNotFound] on a desktop too old to have the route.
  Future<ViewerPanes> panes() async {
    final data = await _get('/agentmux/viewer/panes');
    final panes = parsePanes(data);
    if (panes == null) throw const FormatException('not a panes body');
    return ViewerPanes(
      panes: panes,
      terminalsShared: data is Map && data['terminals_shared'] == true,
    );
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
        403 => const ViewerForbidden(),
        404 => const ViewerNotFound(),
        _ => e,
      };

  /// Opens one agent's feed. Emits `null` once the server accepted the
  /// stream and again for every chunk received (heartbeats included: proof
  /// of life), and each [FeedEvent]. Errors with [ViewerUnauthorized],
  /// [ViewerNotFound], a [TimeoutException] after [idleTimeout] of silence,
  /// or the network error.
  Stream<FeedEvent?> feed(String agent, {String? lastEventId}) => _events(
        '/agentmux/viewer/agents/${Uri.encodeComponent(agent)}/feed',
        lastEventId,
        parseFeedEvent,
      );

  /// Opens one terminal's feed, as [feed] does an agent's. Also errors with
  /// [ViewerForbidden] while the computer doesn't share its terminals.
  Stream<TerminalEvent?> terminalFeed(String blockId, {String? lastEventId}) =>
      _events(
        '/agentmux/viewer/terminals/${Uri.encodeComponent(blockId)}/feed',
        lastEventId,
        parseTerminalEvent,
      );

  /// An event stream at [path], each event parsed by [parse] (null: skipped).
  Stream<T?> _events<T>(
    String path,
    String? lastEventId,
    T? Function(SseEvent) parse,
  ) {
    final cancel = CancelToken();
    StreamSubscription<List<int>>? bytesSub;
    late final StreamController<T?> out;
    out = StreamController<T?>(
      onListen: () async {
        try {
          final res = await _dio.get<ResponseBody>(
            path,
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
              final event = parse(e);
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

  static List<ViewerPane>? parsePanes(Object? json) {
    if (json is! Map) return null;
    final list = json['panes'];
    if (list is! List) return null;
    return [
      for (final p in list.take(2000))
        if (_pane(p) case final pane?) pane,
    ];
  }

  /// One pane; null when it lacks an id, a known kind or a place.
  static ViewerPane? _pane(Object? p) {
    if (p is! Map) return null;
    final blockId = _short(p['block_id']);
    final kind = switch (p['kind']) {
      'agent' => PaneKind.agent,
      'terminal' => PaneKind.terminal,
      'other' => PaneKind.other,
      _ => null,
    };
    final windowId = _short(p['window_id']);
    final tabId = _short(p['tab_id']);
    if (blockId == null || blockId.isEmpty || kind == null) return null;
    if (windowId == null || tabId == null) return null;
    final running = p['running'];
    final agent = _short(p['agent']);
    return ViewerPane(
      blockId: blockId,
      view: _short(p['view']) ?? '',
      kind: kind,
      label: _short(p['label']) ?? '',
      windowId: windowId,
      window: _short(p['window']) ?? '',
      tabId: tabId,
      tab: _short(p['tab']) ?? '',
      tabActive: p['tab_active'] == true,
      agent: agent == null || agent.isEmpty ? null : agent,
      running: running is bool ? running : null,
      parentBlockId: _short(p['parent_block_id']),
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
