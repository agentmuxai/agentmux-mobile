import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/fleet/fleet_snapshot.dart';
import 'package:agentmux_mobile/core/fleet/fleet_transport.dart';
import 'package:agentmux_mobile/core/fleet/sse.dart';

/// Answers every request with [status] and the chunks of [body], then
/// leaves the stream open (as a live SSE connection does) unless [endAfterBody].
class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.status = 200, this.endAfterBody = false});
  final List<String> body;
  final int status;
  final bool endAfterBody;
  StreamController<Uint8List>? controller;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final c = StreamController<Uint8List>();
    controller = c;
    for (final chunk in body) {
      c.add(Uint8List.fromList(utf8.encode(chunk)));
    }
    if (endAfterBody) unawaited(c.close());
    return ResponseBody(c.stream, status);
  }

  @override
  void close({bool force = false}) {}
}

HttpFleetTransport _transport(_Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://192.168.1.230:29704'))
    ..httpClientAdapter = adapter;
  return HttpFleetTransport('192.168.1.230', 29704, 'k', dio: dio);
}

const _event =
    'event: fleet\nid: e1:2\ndata: {"epoch":"e1","rev":2,"hostname":"narko",'
    '"channel":"local-main","version":"0.59.7","agents":["Clamk"]}\n\n';

void main() {
  test('events: accepted, then the fleet snapshot', () async {
    final items = await _transport(_Adapter(['retry: 3000\n\n', _event], endAfterBody: true))
        .events()
        .toList();
    expect(items.first, isNull);
    final snap = items.whereType<FleetSnapshot>().single;
    expect(snap.eventId, 'e1:2');
    expect(snap.agents, ['Clamk']);
  });

  test('a 404 is FleetFeedUnsupported, so the session falls back', () async {
    await expectLater(
      _transport(_Adapter(const [], status: 404)).events().toList(),
      throwsA(isA<FleetFeedUnsupported>()),
    );
  });

  test('an over-long line ends the stream with an error instead of looking live',
      () async {
    final adapter = _Adapter(['data: ${'x' * (SseParser.maxLineLength + 10)}']);
    final items = <FleetSnapshot?>[];
    Object? error;
    final done = Completer<void>();
    _transport(adapter).events().listen(
          items.add,
          onError: (Object e) => error = e,
          onDone: done.complete,
        );
    await done.future.timeout(const Duration(seconds: 5));
    expect(error, isA<FormatException>());
    // Only the "accepted" signal; the poisoned chunk is not proof of life.
    expect(items, [null]);
    // And it stopped reading.
    expect(adapter.controller!.hasListener, isFalse);
  });
}
