import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/secure_store.dart';
import 'package:dio/dio.dart';

/// Placeholder values only: documentation addresses, made-up ids.
const testFingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const testInstallId = 'testinstallidtestinstallid';

class InMemorySecureStore implements SecureStore {
  final values = <String, String>{};
  var writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

PairedHost testPairedHost({
  String id = 'p1',
  String hostname = 'host-a',
  String? channel = 'stable',
  String? installId = testInstallId,
  String host = '198.51.100.20',
  int port = 29800,
  bool invalid = false,
}) =>
    PairedHost(
      id: id,
      token: 'amxv_testtoken',
      fingerprint: testFingerprint,
      host: host,
      port: port,
      hostname: hostname,
      channel: channel,
      installId: installId,
      deviceId: 'dev-1',
      pairedAt: DateTime.utc(2026, 10, 7),
      invalid: invalid,
    );

/// One scripted answer of [FakeAdapter].
class FakeResponse {
  const FakeResponse(this.status, {this.json, this.chunks, this.keepOpen = false});
  final int status;
  final Object? json;

  /// Raw body chunks (an event stream), instead of [json].
  final List<String>? chunks;

  /// Leave the body open after [chunks], as a live stream is.
  final bool keepOpen;
}

/// A Dio adapter that records each request and answers from a script (the
/// last answer repeats).
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.script);
  final List<FakeResponse> script;
  final requests = <RequestOptions>[];
  final bodies = <Object?>[];
  final open = <StreamController<Uint8List>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    bodies.add(options.data);
    final r = script[(requests.length - 1).clamp(0, script.length - 1)];
    final c = StreamController<Uint8List>();
    open.add(c);
    final chunks = r.chunks ?? [if (r.json != null) jsonEncode(r.json)];
    for (final chunk in chunks) {
      c.add(Uint8List.fromList(utf8.encode(chunk)));
    }
    if (!r.keepOpen) unawaited(c.close());
    return ResponseBody(
      c.stream,
      r.status,
      headers: {
        Headers.contentTypeHeader: [
          r.chunks != null ? 'text/event-stream' : Headers.jsonContentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
