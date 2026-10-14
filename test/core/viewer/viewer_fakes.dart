import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/viewer/device_key_store.dart';
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

/// A key store that keeps what it is asked to make in memory. Its "public
/// key" is 65 made-up bytes and its "signature" is the text it was asked to
/// sign, so a test can see what was signed.
class FakeDeviceKeyStore implements DeviceKeyStore {
  final keys = <String, Uint8List>{};
  final deleted = <String>[];
  var failCreate = false;

  @override
  Future<Uint8List> create(String alias) async {
    if (failCreate) throw const DeviceKeyException('no key store');
    final key = Uint8List.fromList([0x04, ...List.filled(64, keys.length + 1)]);
    keys[alias] = key;
    return key;
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    if (!keys.containsKey(alias)) throw const DeviceKeyException('no such key');
    return data;
  }

  @override
  Future<void> delete(String alias) async {
    keys.remove(alias);
    deleted.add(alias);
  }
}
