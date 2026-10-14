// A stand-in for a desktop's viewer listener, for testing the phone app's
// feeds without a desktop build and for breaking them on purpose:
//
//   dart run scripts/fake_viewer.dart [--port 29799] [--turns 600] [--rate-ms 200] [--host 10.0.2.2] [--old-desktop]
//
// It serves a made-up long transcript, a terminal and live CPU/memory over TLS
// with a certificate made for the run, and prints an `agentmux://pair` link
// (base64 it into `AGENTMUX_DEV_PAIR_B64`, see CLAUDE.md). `--host` is the
// address the phone reaches this machine at (10.0.2.2 from the emulator).
// It takes the phone's device key at pairing and checks the signature of a
// message sent to an agent (needs `openssl` on the PATH), then adds it to the
// feed as the computer does. `--old-desktop` acts like an AgentMux from before
// sending: it refuses a 65-byte key and says nothing of `send` in hello. It
// listens on loopback only. Control it with curl, no token:
//
//   /ctl/stats               open streams and request counts, as JSON
//   /ctl/drop                close every open stream (the phone should reconnect)
//   /ctl/revoke  /ctl/restore  answer 401 to the token / accept it again
//   /ctl/blackhole?on=1|0    stop answering authorised requests (never reply)
//   /ctl/mute?on=1|0         keep streams open but send nothing, heartbeats too
//   /ctl/slow?ms=3000        delay every non-stream reply
//   /ctl/burst?lines=500     append that many transcript lines at once
//   /ctl/big?kb=60&n=50      append n tool results of that size
//
// Development only: nothing here is the real protocol's server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _token = 'amxv_fakeviewertoken';
const _code = 'FAKEPAIR22';
/// A new one each run, as after a desktop restart.
final _gen = 'g${DateTime.now().millisecondsSinceEpoch}';

late final int port;
var _turns = 600;
var _rateMs = 200;
var _revoked = false;
var _blackhole = false;
var _mute = false;
var _slowMs = 0;
var _oldDesktop = false;

/// The public key the phone sent at pairing (65 bytes, uncompressed P-256).
Uint8List? _deviceKey;
final _sent = <String, int>{};

final _lines = <String>[];
final _term = BytesBuilder();
final _ticks = StreamController<void>.broadcast();
final _open = <String, int>{};
final _requests = <String, int>{};
final _sinks = <_Sink>{};

String _lorem(int chars, [int seed = 0]) {
  final b = StringBuffer();
  var i = seed;
  while (b.length < chars) {
    b.write('line $i: output from a tool, paths /a/b/c.dart and numbers ${i * 7919}\n');
    i++;
  }
  return b.toString().substring(0, chars);
}

String _f(Map<String, Object?> m) => jsonEncode(m);

/// One turn of a transcript, as the desktop's frames: a prompt, an answer, a
/// shell call and its result, a file read and its result, the turn's end.
List<String> _turn(int n, {int resultChars = 3000}) => [
      _f({'type': 'user', 'message': {'role': 'user', 'content': 'please do thing $n'}}),
      _f({
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': '## Step $n\n\n${_lorem(900, n)}\n\n```dart\nvoid f$n() {\n  print($n);\n}\n```\n'},
          ],
          'stop_reason': 'end_turn',
        },
      }),
      _f({
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 'b$n', 'name': 'Bash', 'input': {'command': 'ls -la /some/dir/$n', 'description': 'list'}},
          ],
          'stop_reason': 'tool_use',
        },
      }),
      _f({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'b$n', 'content': _lorem(resultChars, n)},
          ],
        },
      }),
      _f({
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 'r$n', 'name': 'Read', 'input': {'file_path': '/a/b/file$n.dart'}},
          ],
          'stop_reason': 'tool_use',
        },
      }),
      _f({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'r$n', 'content': _lorem(resultChars, n + 1)},
          ],
        },
      }),
      _f({'type': 'result', 'subtype': 'success', 'duration_ms': 1000, 'is_error': false}),
    ];

var _nextTurn = 0;
void _addTurn({int resultChars = 3000}) => _lines.addAll(_turn(_nextTurn++, resultChars: resultChars));

void _addTermLine() {
  final n = _term.length;
  final text = _lorem(40, n).replaceAll('\n', ' ');
  _term.add(utf8.encode('\x1b[32m[$n]\x1b[0m output $text\r\n'));
}

Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  port = int.parse(arg('port', '29799'));
  _turns = int.parse(arg('turns', '600'));
  _rateMs = int.parse(arg('rate-ms', '200'));
  _oldDesktop = args.contains('--old-desktop');
  final phoneHost = arg('host', '10.0.2.2');

  final dir = Directory('${Directory.systemTemp.path}/amx-fake-viewer')..createSync(recursive: true);
  final certFile = File('${dir.path}/cert.pem');
  final keyFile = File('${dir.path}/key.pem');
  if (!certFile.existsSync() || !keyFile.existsSync()) {
    final r = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '30', '-subj', '/CN=fake-viewer',
      '-keyout', keyFile.path, '-out', certFile.path,
    ]);
    if (r.exitCode != 0) {
      stderr.writeln('openssl failed: ${r.stderr}');
      exit(1);
    }
  }
  final pem = certFile.readAsStringSync();
  final body = pem.split('\n').where((l) => l.isNotEmpty && !l.startsWith('-----')).join();
  final fingerprint = sha256.convert(base64Decode(body)).toString();

  final context = SecurityContext()
    ..useCertificateChain(certFile.path)
    ..usePrivateKey(keyFile.path);

  _lines.add(_f({'type': 'system', 'subtype': 'init', 'session_id': 'fake', 'model': 'model-x'}));
  for (var i = 0; i < _turns; i++) {
    _addTurn();
  }
  for (var i = 0; i < 200; i++) {
    _addTermLine();
  }

  final pending = <String>[];
  Timer.periodic(Duration(milliseconds: _rateMs), (_) {
    if (pending.isEmpty) pending.addAll(_turn(_nextTurn++));
    _lines.add(pending.removeAt(0));
    _ticks.add(null);
  });
  Timer.periodic(const Duration(milliseconds: 300), (_) {
    _addTermLine();
    _ticks.add(null);
  });

  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, port, context);
  final link = 'agentmux://pair?v=1&host=$phoneHost&port=$port&fp=$fingerprint&code=$_code&hostname=fake-desk&channel=fake';
  stdout
    ..writeln('fake viewer on https://127.0.0.1:$port, ${_lines.length} lines')
    ..writeln('pair link: $link')
    ..writeln('base64:    ${base64.encode(utf8.encode(link))}');
  await for (final req in server) {
    unawaited(_handle(req).catchError((Object e, StackTrace st) {
      stderr.writeln('fake viewer: ${req.method} ${req.uri.path}: $e\n$st');
      try {
        req.response.statusCode = 500;
        req.response.close();
      } catch (_) {}
    }));
  }
}

Future<void> _json(HttpResponse res, Object body, {int status = 200}) async {
  res
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await res.close();
}

bool get _alive => !_revoked;

Future<void> _handle(HttpRequest req) async {
  final res = req.response;
  final path = req.uri.path;
  final route = path.replaceAllMapped(RegExp(r'/(agents|terminals)/[^/]+'), (m) => '/${m[1]}/_');
  _requests[route] = (_requests[route] ?? 0) + 1;

  if (path.startsWith('/ctl/')) return _control(req);

  if (path == '/agentmux/viewer/pair' && req.method == 'POST') {
    final data = jsonDecode(await utf8.decoder.bind(req).join());
    if (data is! Map || data['code'] != _code) return _json(res, {'error': 'bad code'}, status: 401);
    final key = data['device_key'];
    if (key != null) {
      Uint8List? bytes;
      try {
        bytes = base64Decode(key as String);
      } catch (_) {}
      final ok = _oldDesktop ? bytes?.length == 32 : (bytes?.length == 65 && bytes![0] == 4);
      if (!ok) {
        return _json(res, {'error': 'device_key must be standard base64 of a 32-byte public key'}, status: 400);
      }
      _deviceKey = _oldDesktop ? null : bytes;
    } else {
      _deviceKey = null;
    }
    _revoked = false;
    return _json(res, {
      'token': _token,
      'device_id': 'dev-fake',
      'hostname': 'fake-desk',
      'channel': 'fake',
      'version': '0.0.0-fake',
    });
  }

  if (req.headers.value('authorization') != 'Bearer $_token' || !_alive) {
    return _json(res, {'error': 'unauthorized'}, status: 401);
  }
  if (_blackhole) {
    await Future<void>.delayed(const Duration(hours: 1));
    return;
  }

  final accept = req.headers.value('accept') ?? '';
  if (_slowMs > 0 && !accept.contains('event-stream')) {
    await Future<void>.delayed(Duration(milliseconds: _slowMs));
  }

  switch (path) {
    case '/agentmux/viewer/hello':
      return _json(res, {
        'hostname': 'fake-desk',
        'device_id': 'dev-fake',
        'channel': 'fake',
        'version': '0.0.0-fake',
        if (!_oldDesktop) 'send': _deviceKey == null ? 'pair_again' : 'allowed',
      });
    case '/agentmux/viewer/agents':
      final now = DateTime.now().millisecondsSinceEpoch;
      return _json(res, {
        'now_ms': now,
        'agents': [
          {'name': 'alpha', 'kind': 'host', 'state': 'working', 'since_ms': now - 60000},
          {'name': 'beta', 'kind': 'host', 'state': 'idle', 'since_ms': now - 600000},
        ],
      });
    case '/agentmux/viewer/panes':
      return _json(res, {
        'terminals_shared': true,
        'panes': [
          for (final t in ['term1', 'term2'])
            {'block_id': t, 'view': 'term', 'kind': 'terminal', 'label': t, 'window_id': 'w1', 'window': 'Window', 'tab_id': 't1', 'tab': 'Tab', 'tab_active': true, 'running': true},
        ],
      });
    case '/agentmux/viewer/sysinfo':
      return _json(res, _sample());
    case '/agentmux/viewer/procs':
      return _json(res, {
        'cpu_count': 8,
        'interval_ms': 3000,
        'tasks': [],
        'machine': {'cpu': 1.2, 'mem': 8 << 30, 'processes': 300},
        'host': {
          'total': 300,
          'matched': 3,
          'processes': [
            for (var i = 0; i < 3; i++) {'pid': 100 + i, 'name': 'proc$i', 'cpu': 0.1 * i, 'mem': 100 << 20},
          ],
        },
      });
    case '/agentmux/viewer/sysinfo/feed':
      return _stream(req, 'sysinfo', (sink, resumed) => _sysinfoLoop(sink));
  }
  final input = RegExp(r'^/agentmux/viewer/agents/([^/]+)/input$').firstMatch(path);
  if (input != null && req.method == 'POST') return _input(req);
  final feed = RegExp(r'^/agentmux/viewer/agents/([^/]+)/feed$').firstMatch(path);
  if (feed != null) return _stream(req, 'feed', _feedLoop);
  final term = RegExp(r'^/agentmux/viewer/terminals/([^/]+)/feed$').firstMatch(path);
  if (term != null) return _stream(req, 'terminal', _termLoop);
  return _json(res, {'error': 'not found'}, status: 404);
}

Map<String, Object?> _sample() {
  final t = DateTime.now().millisecondsSinceEpoch;
  return {
    'ts': t,
    'values': {
      'cpu': 20 + (t ~/ 1000 % 30),
      for (var i = 0; i < 8; i++) 'cpu:$i': 10 + (t ~/ 1000 + i * 7) % 60,
      'mem:used': 9.5,
      'mem:total': 16,
    },
  };
}

class _Sink {
  _Sink(this.res);
  final HttpResponse res;
  bool closed = false;

  void send(String event, Object data, {String? id}) {
    if (closed || _mute) return;
    res.write('event: $event\n${id == null ? '' : 'id: $id\n'}data: ${jsonEncode(data)}\n\n');
  }

  void comment() {
    if (!closed && !_mute) res.write(': hb\n\n');
  }
}

Future<void> _stream(
  HttpRequest req,
  String kind,
  Future<void> Function(_Sink sink, String? lastEventId) loop,
) async {
  final res = req.response
    ..statusCode = 200
    ..bufferOutput = false
    ..headers.contentType = ContentType('text', 'event-stream')
    ..headers.set('cache-control', 'no-cache');
  _open[kind] = (_open[kind] ?? 0) + 1;
  final sink = _Sink(res);
  _sinks.add(sink);
  final hb = Timer.periodic(const Duration(seconds: 15), (_) => sink.comment());
  unawaited(res.done.then((_) => sink.closed = true, onError: (Object _) => sink.closed = true));
  try {
    res.write(': open\n\n');
    await loop(sink, req.headers.value('last-event-id'));
  } catch (_) {
    // The client went away.
  } finally {
    hb.cancel();
    _sinks.remove(sink);
    _open[kind] = (_open[kind] ?? 1) - 1;
    try {
      await res.close();
    } catch (_) {}
  }
}

Future<void> _sysinfoLoop(_Sink sink) async {
  while (!sink.closed) {
    sink.send('sample', _sample());
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

Future<void> _feedLoop(_Sink sink, String? lastEventId) async {
  var next = _lines.length;
  final resume = lastEventId?.split(':');
  if (resume != null && resume.length == 2 && resume[0] == _gen && int.tryParse(resume[1]) != null) {
    next = int.parse(resume[1]).clamp(0, _lines.length);
  } else {
    // The desktop sends the last 50 turns or 256 KB.
    var from = _lines.length;
    var bytes = 0;
    while (from > 0 && bytes < 256 * 1024) {
      bytes += _lines[--from].length;
    }
    sink.send(
      'snapshot',
      {'provider': 'claude', 'gen': _gen, 'from_line': from, 'next_line': _lines.length, 'lines': _lines.sublist(from)},
      id: '$_gen:${_lines.length}',
    );
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  sink.send('status', {'state': 'working', 'since_ms': now - 60000, 'now_ms': now});
  await for (final _ in _ticks.stream) {
    if (sink.closed) return;
    if (next < _lines.length) {
      sink.send('append', {'gen': _gen, 'line': next, 'lines': _lines.sublist(next)}, id: '$_gen:${_lines.length}');
      next = _lines.length;
    }
  }
}

Future<void> _termLoop(_Sink sink, String? lastEventId) async {
  var next = _term.length;
  final resume = int.tryParse(lastEventId ?? '');
  if (resume != null && resume <= _term.length) {
    next = resume;
  } else {
    final all = _term.toBytes();
    final from = all.length > 64 * 1024 ? all.length - 64 * 1024 : 0;
    sink.send(
      'snapshot',
      {'offset': from, 'next_offset': all.length, 'data64': base64.encode(all.sublist(from)), 'rows': 30, 'cols': 100},
      id: '${all.length}',
    );
  }
  await for (final _ in _ticks.stream) {
    if (sink.closed) return;
    if (next < _term.length) {
      final all = _term.toBytes();
      sink.send('append', {'offset': next, 'data64': base64.encode(all.sublist(next))}, id: '${all.length}');
      next = all.length;
    }
  }
}

Future<void> _control(HttpRequest req) async {
  final q = req.uri.queryParameters;
  switch (req.uri.path) {
    case '/ctl/drop':
      // Each stream's loop sees this and ends; its response is then closed.
      for (final s in _sinks) {
        s.closed = true;
      }
    case '/ctl/revoke':
      _revoked = true;
    case '/ctl/restore':
      _revoked = false;
    case '/ctl/blackhole':
      _blackhole = q['on'] != '0';
    case '/ctl/mute':
      _mute = q['on'] != '0';
    case '/ctl/slow':
      _slowMs = int.tryParse(q['ms'] ?? '') ?? 0;
    case '/ctl/burst':
      final n = int.tryParse(q['lines'] ?? '') ?? 100;
      for (var i = 0; i < n; i += 7) {
        _addTurn();
      }
      _ticks.add(null);
    case '/ctl/big':
      final kb = int.tryParse(q['kb'] ?? '') ?? 60;
      final n = int.tryParse(q['n'] ?? '') ?? 10;
      for (var i = 0; i < n; i++) {
        _addTurn(resultChars: kb * 1024);
      }
      _ticks.add(null);
  }
  return _json(req.response, {
    'open': _open,
    'requests': _requests,
    'lines': _lines.length,
    'sent': _sent.keys.toList(),
    'revoked': _revoked,
    'blackhole': _blackhole,
    'slow_ms': _slowMs,
  });
}

/// `POST /agentmux/viewer/agents/:name/input`, as the computer answers it.
Future<void> _input(HttpRequest req) async {
  final res = req.response;
  if (_oldDesktop) return _json(res, {'error': 'not found'}, status: 404);
  final bodyBytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
  final key = _deviceKey;
  if (key == null) return _json(res, {'error': 'no key', 'reason': 'pair_again'}, status: 403);
  final ts = int.tryParse(req.headers.value('x-amxv-timestamp') ?? '');
  final sig = req.headers.value('x-amxv-signature');
  if (ts == null || sig == null) return _json(res, {'error': 'unsigned', 'reason': 'bad_signature'}, status: 403);
  if ((DateTime.now().millisecondsSinceEpoch - ts).abs() > 60000) {
    return _json(res, {'error': 'stale', 'reason': 'stale_timestamp'}, status: 403);
  }
  final text = [
    'amxv-sig-v1',
    req.method,
    req.uri.path,
    '$ts',
    sha256.convert(bodyBytes).toString(),
  ].join('\n');
  if (!await _verifies(key, utf8.encode(text), base64Decode(sig))) {
    return _json(res, {'error': 'bad signature', 'reason': 'bad_signature'}, status: 403);
  }
  final Object? body;
  try {
    body = jsonDecode(utf8.decode(bodyBytes));
  } catch (_) {
    return _json(res, {'error': 'bad body'}, status: 400);
  }
  final message = body is Map ? body['message'] : null;
  final id = body is Map ? body['message_id'] : null;
  if (message is! String || message.trim().isEmpty || id is! String) return _json(res, {'error': 'bad body'}, status: 400);
  if (utf8.encode(message).length > 10000) return _json(res, {'error': 'too long'}, status: 413);
  final duplicate = _sent.containsKey(id);
  _sent[id] = 1;
  if (!duplicate) {
    // What the computer stores for a phone's message: a user turn with `amx`.
    _lines.add(_f({
      'type': 'user',
      'message': {'role': 'user', 'content': message},
      'amx': {'via': 'viewer', 'device': 'Fake phone', 'message_id': id},
    }));
    _ticks.add(null);
  }
  return _json(res, {'message_id': id, 'state': 'delivered', if (duplicate) 'duplicate': true}, status: 202);
}

/// Checks [signature] (DER) over [message] against the P-256 point [key] with
/// `openssl`, which is not the code under test.
Future<bool> _verifies(Uint8List key, List<int> message, List<int> signature) async {
  final dir = Directory.systemTemp.createTempSync('amx-sig');
  try {
    // The fixed SubjectPublicKeyInfo header of a P-256 key, then the point.
    const header = '3059301306072a8648ce3d020106082a8648ce3d030107034200';
    final der = [
      for (var i = 0; i < header.length; i += 2) int.parse(header.substring(i, i + 2), radix: 16),
      ...key,
    ];
    File('${dir.path}/key.der').writeAsBytesSync(der);
    File('${dir.path}/msg').writeAsBytesSync(message);
    File('${dir.path}/sig').writeAsBytesSync(signature);
    final r = await Process.run('openssl', [
      'dgst', '-sha256', '-verify', '${dir.path}/key.der', '-keyform', 'DER', '-signature', '${dir.path}/sig', '${dir.path}/msg',
    ]);
    return r.exitCode == 0;
  } finally {
    dir.deleteSync(recursive: true);
  }
}
